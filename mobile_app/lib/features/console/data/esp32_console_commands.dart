import 'dart:async';
import '../models/console_command.dart';
import '../models/console_state.dart';
import 'console_http_transport.dart';
import 'esp32_console_parser.dart';

/// Outcomes describe firmware reports, never sensor proof of delivered food/liquid.
class Esp32ConsoleCommands {
  Esp32ConsoleCommands({
    required this.state,
    required this.send,
    required this.refresh,
    required this.notify,
    this.confirmationWindow = const Duration(seconds: 12),
  });
  final ConsoleState Function() state;
  final Future<ConsoleHttpResponse> Function(ConsoleAction) send;
  final Future<void> Function(ConsoleAction) refresh;
  final void Function() notify;
  final Duration confirmationWindow;
  final Map<String, ConsoleCommand> _history = {};
  final Map<ConsoleActuator, ConsoleCommand> latest = {};
  final Map<String, _Evidence> _evidence = {};
  int _sequence = 0;
  int _generation = 0;
  bool _disposed = false;
  ConsoleCommand? last;
  ConsoleCommand? get(String id) => _history[id];
  List<ConsoleCommand> get uncertain => _history.values
      .where((c) => c.status == ConsoleCommandStatus.unknown)
      .toList();

  Future<ConsoleCommand> submit(ConsoleAction action) async {
    if (_disposed) throw StateError('Console disposed');
    final current = state();
    final equipment = current.equipment;
    final existing = latest[action.actuator];
    final pump = action.actuator == ConsoleActuator.pumpA
        ? equipment.pumpA
        : equipment.pumpB;
    final pumpPending = latest.values.any(
      (c) => c.action.isPump && c.status.isPending,
    );
    String? refusal;
    if (!current.localConnected || current.readingsStale) {
      refusal = 'Local device unavailable. No request sent.';
    } else if ((existing?.status.isPending == true ||
            (action.isPump && pumpPending)) &&
        (!action.isStop || existing?.action.isStop == true)) {
      refusal = 'An operation is already pending. No request sent.';
    } else if (action.actuator == ConsoleActuator.light &&
            !equipment.lightConfirmed ||
        action.actuator == ConsoleActuator.uv && !equipment.uvConfirmed) {
      refusal = 'Equipment state unavailable. No request sent.';
    } else if (action == ConsoleAction.feed &&
        (!equipment.feederConfirmed ||
            equipment.feederRunning ||
            equipment.feedCount == null)) {
      refusal = 'Feeder busy or status unavailable. No request sent.';
    } else if (action.isPump) {
      if (pump.active == null ||
          (!action.isStop && equipment.pumpA.active == null) ||
          (!action.isStop && equipment.pumpB.active == null)) {
        refusal = 'Pump state unavailable. No request sent.';
      } else if (!action.isStop &&
          (equipment.pumpA.active == true || equipment.pumpB.active == true)) {
        refusal = 'A pump is already active. No request sent.';
      } else if (action.isDispense &&
          (!pump.validDose ||
              pump.doseCount == null ||
              pump.volumeKnown != true ||
              pump.remainingMl == null ||
              pump.remainingMl! + .001 < pump.volumeMl!)) {
        refusal =
            'Check the reported dose, remaining liquid and refill confirmation. No request sent.';
      } else if (action.isRefill &&
          (pump.capacityMl == null ||
              pump.capacityMl! <= 0 ||
              pump.capacityMl! > 5)) {
        refusal = 'Syringe capacity unavailable. No request sent.';
      }
    }
    final command = ConsoleCommand(
      id: 'local-${++_sequence}',
      action: action,
      status: refusal == null
          ? ConsoleCommandStatus.sending
          : ConsoleCommandStatus.rejected,
      message: refusal ?? 'Sending one local request.',
    );
    _history[command.id] = command;
    // A duplicate refusal must not hide an in-flight operation.
    if (refusal != null && existing?.status.isPending == true) return command;
    if (action.isStop && existing?.status.isPending == true) {
      _set(
        existing!,
        ConsoleCommandStatus.unknown,
        'Stop requested; prior movement/delivery is unverified.',
      );
      _evidence.remove(existing.id)?.timer?.cancel();
    }
    latest[action.actuator] = command;
    last = command;
    if (_history.length > 100) {
      final removable = _history.keys
          .where(
            (id) =>
                _history[id]?.status != ConsoleCommandStatus.unknown &&
                !latest.values.any((c) => c.id == id),
          )
          .toList();
      if (removable.isNotEmpty) _history.remove(removable.first);
    }
    notify();
    if (refusal != null) return command;
    final evidence = _Evidence(
      command,
      action == ConsoleAction.feed ? equipment.feedCount : pump.doseCount,
    );
    _evidence[command.id] = evidence;
    final generation = _generation;
    unawaited(_execute(evidence, generation));
    return command;
  }

  Future<void> _execute(_Evidence evidence, int generation) async {
    final command = evidence.command;
    try {
      final response = await send(command.action);
      if (_disposed || generation != _generation) return;
      final body = Esp32ConsoleParser.object(response.body);
      final key = command.action.isDispense || command.action.isRetract
          ? (command.action.isDispense ? 'dispensed' : 'retracted')
          : command.action.isStop
          ? 'stopped'
          : command.action.isRefill
          ? 'refill_confirmed'
          : command.action == ConsoleAction.feed
          ? 'fed'
          : 'led';
      if (body[key] == false &&
          (response.statusCode == 409 ||
              response.statusCode == 503 ||
              response.statusCode == 200)) {
        final reason = body['reason'];
        _set(
          command,
          ConsoleCommandStatus.rejected,
          reason is String && reason.isNotEmpty
              ? 'Device refused: ${reason.substring(0, reason.length > 240 ? 240 : reason.length)}'
              : 'Device refused the request.',
        );
        _evidence.remove(command.id)?.timer?.cancel();
      } else {
        final expected =
            command.action == ConsoleAction.lightOn ||
                command.action == ConsoleAction.uvOn
            ? 'on'
            : 'off';
        evidence.acknowledged =
            response.statusCode == 200 &&
            (key == 'led' ? body[key] == expected : body[key] == true);
        _set(
          command,
          evidence.acknowledged
              ? ConsoleCommandStatus.confirming
              : ConsoleCommandStatus.unknown,
          evidence.acknowledged
              ? 'Device response received. Checking reported state…'
              : 'Outcome unknown. Do not repeat automatically; checking reported state.',
        );
      }
    } catch (error) {
      if (_disposed || generation != _generation) return;
      final definitelyUnsent =
          error is ConsoleCommandFailure && !error.mayHaveReachedDevice;
      _set(
        command,
        definitelyUnsent
            ? ConsoleCommandStatus.failed
            : ConsoleCommandStatus.unknown,
        definitelyUnsent
            ? 'Could not connect; request was not submitted.'
            : 'Outcome unknown. Request may have reached the device. Never repeated automatically.',
      );
      if (definitelyUnsent) _evidence.remove(command.id);
    }
    evidence.awaitingResponse = false;
    if (_disposed || generation != _generation) return;
    if (_evidence.containsKey(command.id)) {
      evidence.timer = Timer(confirmationWindow, () {
        if (_disposed || generation != _generation) return;
        if (_history[command.id]?.status == ConsoleCommandStatus.confirming) {
          _set(
            command,
            ConsoleCommandStatus.unknown,
            'Unable to confirm the operation. Monitoring device state; no automatic retry.',
          );
          notify();
        }
      });
    }
    notify();
    try {
      await refresh(command.action);
    } catch (_) {
      /* Polling reconciles later. */
    }
  }

  void reconcile(ConsoleEquipmentState equipment, String path) {
    for (final evidence in _evidence.values.toList()) {
      if (evidence.awaitingResponse) continue;
      final command = evidence.command;
      final action = command.action;
      if (action.statusPath != path) continue;
      if (latest[action.actuator]?.id != command.id) continue;
      bool? active;
      int? count;
      bool confirmed = false;
      String? message;
      if (action.actuator == ConsoleActuator.light ||
          action.actuator == ConsoleActuator.uv) {
        final light = action.actuator == ConsoleActuator.light;
        final known = light ? equipment.lightConfirmed : equipment.uvConfirmed;
        final on = light ? equipment.lightOn : equipment.uvOn;
        final wanted =
            action == ConsoleAction.lightOn || action == ConsoleAction.uvOn;
        if (known && on == wanted) {
          confirmed = true;
          message =
              'Device reports ${on ? 'ON' : 'OFF'}. Physical output is not measured.';
        } else if (known) {
          _set(
            command,
            ConsoleCommandStatus.unknown,
            'Device reports ${on ? 'ON' : 'OFF'}, different from the request. Outcome uncertain; schedules/external commands may apply.',
          );
        }
      } else {
        final pump = action.actuator == ConsoleActuator.pumpA
            ? equipment.pumpA
            : equipment.pumpB;
        active = action == ConsoleAction.feed
            ? (equipment.feederConfirmed ? equipment.feederRunning : null)
            : pump.active;
        count = action == ConsoleAction.feed
            ? equipment.feedCount
            : pump.doseCount;
        if (action.isStop) {
          confirmed = active == false;
          message =
              'Device reports motor idle. Delivered amount is unverified.';
        } else if (action.isRefill) {
          confirmed =
              evidence.acknowledged &&
              pump.volumeKnown == true &&
              pump.remainingMl != null &&
              pump.capacityMl != null &&
              (pump.remainingMl! - pump.capacityMl!).abs() <= .001;
          message =
              'Device reports refill recorded. No motor movement; cooldown unchanged.';
        } else if (action.isRetract) {
          if (active == true) evidence.observedActive = true;
          confirmed = evidence.observedActive && active == false;
          message =
              'Device-reported movement ended. Full stroke/refill is not physically measured.';
        } else {
          // Counters increment at START. A larger counter cannot prove delivery or
          // distinguish this request from a schedule/gateway operation.
          if (count != null &&
              evidence.baseline != null &&
              count > evidence.baseline!) {
            evidence.observedStart = true;
          }
          confirmed = evidence.observedStart && active == false;
          message =
              'Device reports a new ${action == ConsoleAction.feed ? 'feed' : 'dose'} start and is now idle. Delivery and command attribution are unverified.';
        }
        if (!confirmed &&
            (evidence.observedStart || evidence.observedActive) &&
            _history[command.id]?.status != ConsoleCommandStatus.unknown) {
          _set(
            command,
            ConsoleCommandStatus.confirming,
            'Device reports activity. Waiting for reported idle; physical delivery is unverified.',
          );
        }
      }
      if (confirmed) {
        _set(command, ConsoleCommandStatus.confirmed, message!);
        _evidence.remove(command.id)?.timer?.cancel();
      } else if (active != null &&
          _history[command.id]?.status == ConsoleCommandStatus.unknown) {
        _set(
          command,
          ConsoleCommandStatus.unknown,
          'Device now reports ${active ? 'active' : 'idle'}. Whether this request executed remains unknown. No automatic retry.',
        );
      }
    }
  }

  void _set(
    ConsoleCommand command,
    ConsoleCommandStatus status,
    String message,
  ) {
    final updated = command.withResult(status, message);
    _history[command.id] = updated;
    if (latest[command.action.actuator]?.id == command.id) {
      latest[command.action.actuator] = updated;
    }
    if (last?.id == command.id) last = updated;
  }

  void cancel() {
    _generation++;
    for (final evidence in _evidence.values) {
      evidence.timer?.cancel();
      final current = _history[evidence.command.id];
      if (current?.status.isPending == true) {
        _set(
          evidence.command,
          ConsoleCommandStatus.unknown,
          'Console session ended. Operation outcome unverified; request will not be replayed.',
        );
      }
    }
    _evidence.clear();
    if (!_disposed) notify();
  }

  void dispose() {
    cancel();
    _disposed = true;
  }
}

class _Evidence {
  _Evidence(this.command, this.baseline);
  final ConsoleCommand command;
  final int? baseline;
  bool awaitingResponse = true,
      acknowledged = false,
      observedStart = false,
      observedActive = false;
  Timer? timer;
}

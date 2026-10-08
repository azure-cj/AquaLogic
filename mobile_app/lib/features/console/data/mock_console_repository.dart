import 'dart:async';
import '../models/console_command.dart';
import '../models/console_state.dart';
import 'console_repository.dart';

/// Deterministic, hardware-free preview of the live command workflow.
/// Nothing in this adapter opens a network connection.
class MockConsoleRepository extends ConsoleRepository
    implements ConsolePrototypeControls {
  MockConsoleRepository({
    DateTime Function()? clock,
    this.runningDelay = const Duration(milliseconds: 450),
    this.completionDelay = const Duration(milliseconds: 1700),
  }) : _clock = clock ?? DateTime.now {
    _state = ConsoleState(
      observedAt: _clock(),
      equipment: ConsoleEquipmentState(
        pumpA: _pump(),
        pumpB: _pump(),
        feedCount: 0,
      ),
    );
  }
  final DateTime Function() _clock;
  final Duration runningDelay, completionDelay;
  late ConsoleState _state;
  final _updates = StreamController<ConsoleState>.broadcast();
  final Map<String, ConsoleCommand> _commands = {};
  final List<Timer> _timers = [];
  var _sequence = 0;
  var _disposed = false;
  DateTime? _nextDoseAt;
  ConsoleCommandStatus? _nextOutcome;

  ConsolePumpState _pump({
    ConsolePumpState? previous,
    bool? active = false,
    double? remaining,
    int? count,
  }) => ConsolePumpState(
    active: active,
    doseCount: count ?? previous?.doseCount ?? 0,
    volumeMl: 1,
    remainingMl: remaining ?? previous?.remainingMl ?? 5,
    capacityMl: 5,
    volumeKnown: true,
    refillRequired: (remaining ?? previous?.remainingMl ?? 5) < 1,
    clockSynced: true,
    nextEligibleAt: _nextDoseAt?.toIso8601String(),
  );

  @override
  bool get supportsPumpControls => true;
  @override
  ConsolePrototypeControls get prototypeControls => this;
  @override
  Future<ConsoleState> getState() async => _state;
  @override
  Stream<ConsoleState> watchState() => Stream.multi((sink) {
    sink.add(_state);
    final subscription = _updates.stream.listen(
      sink.add,
      onError: sink.addError,
      onDone: sink.close,
    );
    sink.onCancel = subscription.cancel;
  });
  @override
  Future<ConsoleEquipmentState> getEquipmentState() async => _state.equipment;
  @override
  Future<ConsoleCommand?> getCommand(String id) async => _commands[id];
  @override
  Stream<ConsoleCommand> watchCommand(String id) => Stream.multi((sink) {
    final current = _commands[id];
    if (current != null) sink.add(current);
    ConsoleCommandStatus? lastStatus = current?.status;
    final subscription = _updates.stream.listen(
      (_) {
        final command = _commands[id];
        if (command != null && command.status != lastStatus) {
          lastStatus = command.status;
          sink.add(command);
        }
      },
      onError: sink.addError,
      onDone: sink.close,
    );
    sink.onCancel = subscription.cancel;
  });
  @override
  Future<ConsoleCommand> setLight(bool enabled) =>
      _submit(enabled ? ConsoleAction.lightOn : ConsoleAction.lightOff);
  @override
  Future<ConsoleCommand> setUV(bool enabled) =>
      _submit(enabled ? ConsoleAction.uvOn : ConsoleAction.uvOff);
  @override
  Future<ConsoleCommand> feed() => _submit(ConsoleAction.feed);
  @override
  Future<ConsoleCommand> pump(ConsoleAction action) {
    if (!action.isPump) throw ArgumentError('Expected a pump action');
    return _submit(action);
  }

  Future<ConsoleCommand> _submit(ConsoleAction action) async {
    if (_disposed) throw StateError('Console repository disposed');
    _timers.removeWhere((timer) => !timer.isActive);
    final existing = _state.commands[action.actuator];
    final pending = existing?.status.isPending == true;
    final equipment = _state.equipment;
    final pump = action.actuator == ConsoleActuator.pumpA
        ? equipment.pumpA
        : equipment.pumpB;
    final confirmed = switch (action.actuator) {
      ConsoleActuator.light => equipment.lightConfirmed,
      ConsoleActuator.uv => equipment.uvConfirmed,
      ConsoleActuator.feeder => equipment.feederConfirmed,
      _ => pump.active != null,
    };
    final outcome = _nextOutcome;
    String? refusal;
    if (!_state.localConnected) {
      refusal = 'Local device offline. No simulated action started.';
    } else if (pending && (!action.isStop || existing!.action.isStop)) {
      refusal = 'Another command for this equipment is still in progress.';
    } else if (!confirmed) {
      refusal =
          'Equipment state unconfirmed. Select Normal to restore a simulated report.';
    } else if (action.isPump &&
        !action.isStop &&
        (equipment.pumpA.active != false ||
            equipment.pumpB.active != false ||
            _state.commands.values.any(
              (c) => c.action.isPump && c.status.isPending,
            ))) {
      refusal = 'Simulated device refused: syringe busy.';
    } else if (action.isDispense &&
        _nextDoseAt != null &&
        _clock().isBefore(_nextDoseAt!)) {
      refusal =
          'Simulated device refused: shared 2-hour chemical cooldown. Next eligible: ${_nextDoseAt!.toIso8601String()}.';
    } else if (action.isDispense &&
        (!pump.validDose ||
            pump.volumeKnown != true ||
            pump.remainingMl == null ||
            pump.remainingMl! < pump.volumeMl!)) {
      refusal =
          'Simulated device refused: configured dose or liquid estimate unavailable.';
    } else if (outcome == ConsoleCommandStatus.rejected) {
      refusal = 'Simulated device rejected this command.';
    }
    if (!pending) _nextOutcome = null;
    final command = ConsoleCommand(
      id: 'prototype-${++_sequence}',
      action: action,
      status: refusal == null
          ? ConsoleCommandStatus.sending
          : ConsoleCommandStatus.rejected,
      message:
          refusal ??
          'Simulation · sending one request. No hardware is connected.',
    );
    _commands[command.id] = command;
    if (refusal != null && pending) return command;
    if (pending && action.isStop) {
      _transition(
        existing!,
        ConsoleCommandStatus.unknown,
        'Simulation · stop requested; prior delivery remains unverified.',
      );
    }
    _publishCommand(command);
    if (refusal != null) return command;
    _timers.add(
      Timer(runningDelay, () {
        if (!_isPending(command.id)) return;
        if (outcome != ConsoleCommandStatus.unknown) {
          var updated = _state.equipment;
          if (action == ConsoleAction.feed) {
            updated = updated.copyWith(
              feederRunning: true,
              feedCount: (updated.feedCount ?? 0) + 1,
            );
          } else if (action.isPump) {
            if (action.isDispense) {
              _nextDoseAt = _clock().add(const Duration(hours: 2));
            }
            final current = action.actuator == ConsoleActuator.pumpA
                ? updated.pumpA
                : updated.pumpB;
            final next = _pump(
              previous: current,
              active: action.isDispense || action.isRetract,
              remaining: action.isDispense
                  ? current.remainingMl! - current.volumeMl!
                  : action.isRefill
                  ? current.capacityMl
                  : null,
              count: action.isDispense ? current.doseCount! + 1 : null,
            );
            updated = action.actuator == ConsoleActuator.pumpA
                ? updated.copyWith(
                    pumpA: next,
                    pumpAStatus: next.active! ? 'RUNNING' : 'IDLE',
                    pumpB: _pump(
                      previous: updated.pumpB,
                      active: updated.pumpB.active,
                    ),
                  )
                : updated.copyWith(
                    pumpB: next,
                    pumpBStatus: next.active! ? 'RUNNING' : 'IDLE',
                    pumpA: _pump(
                      previous: updated.pumpA,
                      active: updated.pumpA.active,
                    ),
                  );
          }
          _publish(_state.copyWith(equipment: updated));
        }
        _transition(
          command,
          ConsoleCommandStatus.confirming,
          'Simulation · response received; checking reported state.',
        );
      }),
    );
    _timers.add(
      Timer(completionDelay, () {
        if (!_isPending(command.id)) return;
        if (outcome == ConsoleCommandStatus.unknown) {
          _transition(
            command,
            ConsoleCommandStatus.unknown,
            'Simulation · response lost. Outcome unknown; no automatic retry.',
          );
          return;
        }
        var updated = _state.equipment;
        switch (action) {
          case ConsoleAction.lightOn:
            updated = updated.copyWith(lightOn: true, lightConfirmed: true);
          case ConsoleAction.lightOff:
            updated = updated.copyWith(lightOn: false, lightConfirmed: true);
          case ConsoleAction.uvOn:
            updated = updated.copyWith(uvOn: true, uvConfirmed: true);
          case ConsoleAction.uvOff:
            updated = updated.copyWith(uvOn: false, uvConfirmed: true);
          case ConsoleAction.feed:
            updated = updated.copyWith(
              feederRunning: false,
              feederConfirmed: true,
            );
          default:
            final current = action.actuator == ConsoleActuator.pumpA
                ? updated.pumpA
                : updated.pumpB;
            final next = _pump(previous: current);
            updated = action.actuator == ConsoleActuator.pumpA
                ? updated.copyWith(pumpA: next, pumpAStatus: 'IDLE')
                : updated.copyWith(pumpB: next, pumpBStatus: 'IDLE');
        }
        _publish(_state.copyWith(equipment: updated));
        _transition(
          command,
          ConsoleCommandStatus.confirmed,
          action.isDispense || action == ConsoleAction.feed || action.isRetract
              ? 'Simulation · reported activity ended. Physical delivery is not verified.'
              : 'Simulation · reported state confirmed. No hardware action occurred.',
        );
      }),
    );
    return command;
  }

  bool _isPending(String id) =>
      !_disposed && _commands[id]?.status.isPending == true;
  void _transition(
    ConsoleCommand command,
    ConsoleCommandStatus status,
    String message,
  ) {
    final updated = command.withResult(status, message);
    var equipment = _state.equipment;
    if (status == ConsoleCommandStatus.unknown) {
      equipment = switch (command.action.actuator) {
        ConsoleActuator.light => equipment.copyWith(lightConfirmed: false),
        ConsoleActuator.uv => equipment.copyWith(uvConfirmed: false),
        ConsoleActuator.feeder => equipment.copyWith(feederConfirmed: false),
        ConsoleActuator.pumpA => equipment.copyWith(
          pumpA: _pump(previous: equipment.pumpA, active: null),
          pumpAStatus: 'UNKNOWN',
        ),
        ConsoleActuator.pumpB => equipment.copyWith(
          pumpB: _pump(previous: equipment.pumpB, active: null),
          pumpBStatus: 'UNKNOWN',
        ),
      };
    }
    _publish(_state.copyWith(equipment: equipment));
    _publishCommand(updated);
  }

  void _publishCommand(ConsoleCommand command) {
    _commands[command.id] = command;
    final latest = {..._state.commands, command.action.actuator: command};
    _publish(
      _state.copyWith(
        command: command,
        commands: Map.unmodifiable(latest),
        uncertainCommands: List.unmodifiable(
          _commands.values.where(
            (c) => c.status == ConsoleCommandStatus.unknown,
          ),
        ),
      ),
    );
  }

  void _publish(ConsoleState state) {
    if (_disposed) return;
    _state = state;
    _updates.add(state);
  }

  @override
  Future<void> applyScenario(ConsoleScenario scenario) async {
    if (_disposed) return;
    if (scenario == ConsoleScenario.resetSimulation) {
      cancelCommands();
      _nextDoseAt = null;
      _nextOutcome = null;
      _commands.clear();
      _publish(
        ConsoleState(
          observedAt: _clock(),
          equipment: ConsoleEquipmentState(
            pumpA: _pump(),
            pumpB: _pump(),
            feedCount: 0,
          ),
        ),
      );
      return;
    }
    final interrupted = _state.commands.values.any((c) => c.status.isPending);
    if (interrupted) cancelCommands();
    _nextOutcome = switch (scenario) {
      ConsoleScenario.rejected => ConsoleCommandStatus.rejected,
      ConsoleScenario.unknown => ConsoleCommandStatus.unknown,
      _ => null,
    };
    final local =
        scenario != ConsoleScenario.localOffline &&
        scenario != ConsoleScenario.bothOffline;
    final restore = scenario == ConsoleScenario.normal && !interrupted;
    _publish(
      _state.copyWith(
        localConnected: local,
        cloudConnected:
            scenario != ConsoleScenario.cloudOffline &&
            scenario != ConsoleScenario.bothOffline,
        ph: scenario == ConsoleScenario.attention
            ? 6.48
            : scenario == ConsoleScenario.critical
            ? 5.8
            : 7.32,
        quality: scenario == ConsoleScenario.attention
            ? ConsoleWaterQuality.attention
            : scenario == ConsoleScenario.critical
            ? ConsoleWaterQuality.critical
            : ConsoleWaterQuality.normal,
        observedAt: local ? _clock() : _state.observedAt,
        equipment: _state.equipment.copyWith(
          feederRunning: false,
          lightConfirmed: restore ? true : null,
          uvConfirmed: restore ? true : null,
          feederConfirmed: restore ? true : null,
          pumpA: restore ? _pump(previous: _state.equipment.pumpA) : null,
          pumpB: restore ? _pump(previous: _state.equipment.pumpB) : null,
          pumpAStatus: restore ? 'IDLE' : null,
          pumpBStatus: restore ? 'IDLE' : null,
        ),
      ),
    );
  }

  @override
  Future<void> retryLocalConnection() async {
    _publish(_state.copyWith(localConnected: true, observedAt: _clock()));
  }

  @override
  void cancelCommands() {
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();
    for (final command in _state.commands.values.toList()) {
      if (command.status.isPending) {
        _transition(
          command,
          ConsoleCommandStatus.unknown,
          'Simulation · session interrupted. Outcome unknown; no automatic replay.',
        );
      }
    }
  }

  @override
  Future<void> dispose() async {
    cancelCommands();
    _disposed = true;
    unawaited(_updates.close());
  }
}

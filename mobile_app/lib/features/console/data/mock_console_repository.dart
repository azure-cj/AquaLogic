import 'dart:async';
import '../models/console_command.dart';
import '../models/console_state.dart';
import 'console_repository.dart';

/// All simulated execution lives here, never in a widget or cloud repository.
class MockConsoleRepository extends ConsoleRepository
    implements ConsolePrototypeControls {
  MockConsoleRepository({
    DateTime Function()? clock,
    this.runningDelay = const Duration(milliseconds: 450),
    this.completionDelay = const Duration(milliseconds: 1700),
  }) : _clock = clock ?? DateTime.now {
    _state = ConsoleState(observedAt: _clock());
  }
  final DateTime Function() _clock;
  final Duration runningDelay;
  final Duration completionDelay;
  late ConsoleState _state;
  final _updates = StreamController<ConsoleState>.broadcast();
  final Map<String, ConsoleCommand> _commands = {};
  final List<Timer> _timers = [];
  var _sequence = 0;
  var _disposed = false;
  ConsoleCommandStatus? _nextOutcome;

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
      (state) {
        final command = state.command;
        if (command?.id == id && command!.status != lastStatus) {
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

  Future<ConsoleCommand> _submit(ConsoleAction action) async {
    if (_disposed) throw StateError('Console repository disposed');
    _timers.removeWhere((timer) => !timer.isActive);
    if (_commands.length >= 100) _commands.remove(_commands.keys.first);
    final busy = _state.command?.status.isPending == true;
    final confirmed = switch (action) {
      ConsoleAction.lightOn ||
      ConsoleAction.lightOff => _state.equipment.lightConfirmed,
      ConsoleAction.uvOn || ConsoleAction.uvOff => _state.equipment.uvConfirmed,
      ConsoleAction.feed => _state.equipment.feederConfirmed,
      _ => false,
    };
    final outcome = _nextOutcome;
    if (!busy) _nextOutcome = null;
    final rejection = !_state.localConnected
        ? 'Local device offline. No action started.'
        : busy
        ? 'Another command is still in progress.'
        : !confirmed
        ? 'Equipment state unconfirmed. Select the normal prototype scenario to simulate a fresh device report.'
        : outcome == ConsoleCommandStatus.rejected
        ? 'Simulated device rejected this command.'
        : null;
    final command = ConsoleCommand(
      id: 'prototype-${++_sequence}',
      action: action,
      status: rejection == null
          ? ConsoleCommandStatus.accepted
          : ConsoleCommandStatus.rejected,
      message: rejection ?? 'Simulated device accepted the command.',
    );
    _commands[command.id] = command;
    // A rejected concurrent submission must not replace the active operation.
    if (busy) return command;
    _publish(_state.copyWith(command: command));
    if (rejection != null) return command;
    _timers.add(
      Timer(runningDelay, () {
        if (!_isPending(command.id)) return;
        _transition(
          command,
          ConsoleCommandStatus.running,
          'Simulated operation in progress.',
        );
        if (action == ConsoleAction.feed) {
          _publish(
            _state.copyWith(
              equipment: _state.equipment.copyWith(feederRunning: true),
            ),
          );
        }
      }),
    );
    _timers.add(
      Timer(completionDelay, () {
        if (!_isPending(command.id)) return;
        if (outcome == ConsoleCommandStatus.unknown) {
          _transition(
            command,
            ConsoleCommandStatus.unknown,
            'Outcome unconfirmed. Equipment state has not been updated.',
          );
          return;
        }
        var equipment = _state.equipment;
        switch (action) {
          case ConsoleAction.lightOn:
            equipment = equipment.copyWith(lightOn: true, lightConfirmed: true);
          case ConsoleAction.lightOff:
            equipment = equipment.copyWith(
              lightOn: false,
              lightConfirmed: true,
            );
          case ConsoleAction.uvOn:
            equipment = equipment.copyWith(uvOn: true, uvConfirmed: true);
          case ConsoleAction.uvOff:
            equipment = equipment.copyWith(uvOn: false, uvConfirmed: true);
          case ConsoleAction.feed:
            equipment = equipment.copyWith(
              feederRunning: false,
              feederConfirmed: true,
            );
          default:
            break;
        }
        _publish(_state.copyWith(equipment: equipment));
        _transition(
          command,
          ConsoleCommandStatus.completed,
          'Simulated operation completed.',
        );
      }),
    );
    return command;
  }

  bool _isPending(String id) =>
      !_disposed &&
      _state.command?.id == id &&
      _state.command!.status.isPending;
  void _transition(
    ConsoleCommand command,
    ConsoleCommandStatus status,
    String message,
  ) {
    final updated = command.withResult(status, message);
    _commands[command.id] = updated;
    var equipment = _state.equipment;
    if (status == ConsoleCommandStatus.unknown) {
      equipment = switch (command.action) {
        ConsoleAction.lightOn ||
        ConsoleAction.lightOff => equipment.copyWith(lightConfirmed: false),
        ConsoleAction.uvOn ||
        ConsoleAction.uvOff => equipment.copyWith(uvConfirmed: false),
        ConsoleAction.feed => equipment.copyWith(feederConfirmed: false),
        _ => equipment,
      };
    }
    _publish(_state.copyWith(command: updated, equipment: equipment));
  }

  void _publish(ConsoleState state) {
    if (_disposed) return;
    _state = state;
    _updates.add(state);
  }

  @override
  Future<void> applyScenario(ConsoleScenario scenario) async {
    if (_disposed) return;
    final interrupted = _state.command?.status.isPending == true;
    if (interrupted) {
      _transition(
        _state.command!,
        ConsoleCommandStatus.unknown,
        'Prototype scenario changed during execution. Outcome unconfirmed.',
      );
    }
    _nextOutcome = switch (scenario) {
      ConsoleScenario.rejected => ConsoleCommandStatus.rejected,
      ConsoleScenario.unknown => ConsoleCommandStatus.unknown,
      _ => null,
    };
    final local =
        scenario != ConsoleScenario.localOffline &&
        scenario != ConsoleScenario.bothOffline;
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
          lightConfirmed: scenario == ConsoleScenario.normal && !interrupted
              ? true
              : null,
          uvConfirmed: scenario == ConsoleScenario.normal && !interrupted
              ? true
              : null,
          feederConfirmed: scenario == ConsoleScenario.normal && !interrupted
              ? true
              : null,
        ),
      ),
    );
  }

  @override
  Future<void> retryLocalConnection() async {
    _publish(_state.copyWith(localConnected: true, observedAt: _clock()));
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();
    // Closing broadcasts done asynchronously; disposal must not wait on a
    // subscriber's paused event delivery (or a test's stopped event clock).
    unawaited(_updates.close());
  }
}

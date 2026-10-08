import 'dart:async';
import 'package:flutter/foundation.dart';
import '../data/console_repository.dart';
import '../models/console_command.dart';
import '../models/console_state.dart';

class ConsoleController extends ChangeNotifier {
  ConsoleController(this.repository);
  final ConsoleRepository repository;
  ConsoleState? state;
  String? error;
  bool _disposed = false;
  bool _submitting = false;
  StreamSubscription<ConsoleState>? _subscription;
  bool get busy => _submitting || state?.command?.status.isPending == true;
  bool get canCommand =>
      !repository.isReadOnly &&
      error == null &&
      state?.localConnected == true &&
      !busy;
  bool canSubmit(ConsoleAction action) {
    if (_disposed ||
        _submitting ||
        repository.isReadOnly ||
        error != null ||
        state?.localConnected != true ||
        state?.readingsStale == true) {
      return false;
    }
    final commands = state!.commands;
    if (action.isStop) {
      return repository.supportsPumpControls &&
          !(commands[action.actuator]?.action.isStop == true &&
              commands[action.actuator]?.status.isPending == true);
    }
    if (commands[action.actuator]?.status.isPending == true) return false;
    if (action.isPump &&
        (!repository.supportsPumpControls ||
            commands.values.any(
              (c) => c.action.isPump && c.status.isPending,
            ))) {
      return false;
    }
    return true;
  }

  bool get hasScenarios => repository.prototypeControls != null;

  void start() {
    _subscription ??= repository.watchState().listen(
      (value) {
        state = value;
        error = null;
        _notify();
      },
      onError: (Object _) {
        error = 'Console data unavailable. Try again.';
        _notify();
      },
    );
  }

  Future<ConsoleCommand?> submit(ConsoleAction action) async {
    if (!canSubmit(action)) return null;
    _submitting = true;
    _notify();
    try {
      final command = await switch (action) {
        ConsoleAction.lightOn => repository.setLight(true),
        ConsoleAction.lightOff => repository.setLight(false),
        ConsoleAction.uvOn => repository.setUV(true),
        ConsoleAction.uvOff => repository.setUV(false),
        ConsoleAction.feed => repository.feed(),
        _ => repository.pump(action),
      };
      state = await repository.getState();
      return command;
    } catch (_) {
      error =
          'Command outcome unknown. Do not repeat the action automatically.';
      return null;
    } finally {
      _submitting = false;
      _notify();
    }
  }

  Future<void> retry() async {
    try {
      await repository.retryLocalConnection();
      state = await repository.getState();
      error = null;
    } catch (_) {
      error = 'Local device still unavailable.';
    }
    _notify();
  }

  Future<void> applyScenario(ConsoleScenario scenario) async {
    await repository.prototypeControls?.applyScenario(scenario);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    repository.cancelCommands();
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}

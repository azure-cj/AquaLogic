import '../models/console_command.dart';
import '../models/console_state.dart';

enum ConsoleScenario {
  normal('Normal'),
  cloudOffline('Cloud unavailable'),
  localOffline('Local device offline'),
  bothOffline('Both unavailable'),
  attention('Water needs attention'),
  critical('Critical water quality'),
  rejected('Next command rejected'),
  unknown('Next command unknown');

  const ConsoleScenario(this.label);
  final String label;
}

/// Optional prototype controls; production adapters do not expose scenarios.
abstract interface class ConsolePrototypeControls {
  Future<void> applyScenario(ConsoleScenario scenario);
}

abstract class ConsoleRepository {
  bool get isReadOnly => false;
  bool get supportsLocalConfiguration => false;
  String? get configuredHost => null;
  Future<void> configureHost(String host) async =>
      throw UnsupportedError('Local configuration unavailable');
  Future<bool> testConnection() async =>
      throw UnsupportedError('Connection test unavailable');
  ConsolePrototypeControls? get prototypeControls => null;
  Future<ConsoleState> getState();
  Stream<ConsoleState> watchState();
  Future<ConsoleEquipmentState> getEquipmentState();
  Future<ConsoleCommand> setLight(bool enabled);
  Future<ConsoleCommand> setUV(bool enabled);
  Future<ConsoleCommand> feed();
  Future<ConsoleCommand?> getCommand(String id);
  Stream<ConsoleCommand> watchCommand(String id);
  Future<void> retryLocalConnection();
  Future<void> dispose();
}

import '../models/console_command.dart';
import '../models/console_state.dart';
import 'console_repository.dart';

/// Phase 2 adapter placeholder. Never selected by Phase 1 composition.
/// No endpoints, credentials, discovery, or networking are implemented.
class Esp32ConsoleRepository extends ConsoleRepository {
  Never _unavailable() =>
      throw UnsupportedError('ESP32 integration is not implemented.');
  @override
  Future<ConsoleState> getState() async => _unavailable();
  @override
  Stream<ConsoleState> watchState() =>
      Stream.error(UnsupportedError('ESP32 integration is not implemented.'));
  @override
  Future<ConsoleEquipmentState> getEquipmentState() async => _unavailable();
  @override
  Future<ConsoleCommand> setLight(bool enabled) async => _unavailable();
  @override
  Future<ConsoleCommand> setUV(bool enabled) async => _unavailable();
  @override
  Future<ConsoleCommand> feed() async => _unavailable();
  @override
  Future<ConsoleCommand?> getCommand(String id) async => _unavailable();
  @override
  Stream<ConsoleCommand> watchCommand(String id) =>
      Stream.error(UnsupportedError('ESP32 integration is not implemented.'));
  @override
  Future<void> retryLocalConnection() async => _unavailable();
  @override
  Future<void> dispose() async {}
}

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ConsoleEndpoint {
  ConsoleEndpoint._(this.host);
  final String host;
  Uri get baseUri => Uri(scheme: 'http', host: host);
  static ConsoleEndpoint parse(String input) {
    final host = input.trim().toLowerCase();
    if (RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(host)) {
      final parts = host.split('.').map(int.parse).toList();
      if (parts.every((v) => v >= 0 && v <= 255) &&
          (parts[0] == 10 ||
              (parts[0] == 172 && parts[1] >= 16 && parts[1] <= 31) ||
              (parts[0] == 192 && parts[1] == 168))) {
        return ConsoleEndpoint._(parts.join('.'));
      }
    } else if (!RegExp(r'^[\d.]+$').hasMatch(host)) {
      final labels = host.split('.');
      if (host.length <= 253 &&
          labels.every(
            (label) => RegExp(
              r'^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$',
            ).hasMatch(label),
          ) &&
          (labels.length == 1 || labels.last == 'local')) {
        return ConsoleEndpoint._(host);
      }
    }
    throw const FormatException(
      'Enter a private Wi-Fi IPv4 address, local hostname, or .local hostname without a URL, port or path.',
    );
  }
}

abstract interface class ConsoleConfigurationStore {
  Future<String?> readHost();
  Future<void> writeHost(String host);
}

class SecureConsoleConfigurationStore implements ConsoleConfigurationStore {
  SecureConsoleConfigurationStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _storage;
  static const key = 'aqualogic_console_host';
  @override
  Future<String?> readHost() => _storage.read(key: key);
  @override
  Future<void> writeHost(String host) =>
      _storage.write(key: key, value: ConsoleEndpoint.parse(host).host);
}

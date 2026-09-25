import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class RefreshCredentialStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> delete();
}

/// Persists only the opaque refresh-cookie value using platform secure storage.
class SecureRefreshCredentialStore implements RefreshCredentialStore {
  SecureRefreshCredentialStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'aqualogic_refresh_credential';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String value) => _storage.write(key: _key, value: value);

  @override
  Future<void> delete() => _storage.delete(key: _key);
}

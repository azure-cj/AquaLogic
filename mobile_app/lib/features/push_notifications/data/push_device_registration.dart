import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:aqualogic/features/auth/data/mock_auth_service.dart';
import 'package:aqualogic/features/push_notifications/data/push_notification_service.dart';
import 'package:aqualogic/shared/network/api_client.dart';

abstract interface class PushDeviceRegistrationRepository {
  Future<void> register({
    required String installationId,
    required String fcmToken,
    required String platform,
  });

  Future<void> deactivate(String installationId);
}

class ApiPushDeviceRegistrationRepository
    implements PushDeviceRegistrationRepository {
  ApiPushDeviceRegistrationRepository({required this.apiClient});

  static const registrationPath = '/push/devices/current';
  final ApiClient apiClient;

  @override
  Future<void> register({
    required String installationId,
    required String fcmToken,
    required String platform,
  }) async {
    await apiClient.put(
      registrationPath,
      authenticated: true,
      body: <String, Object?>{
        'installation_id': installationId,
        'fcm_token': fcmToken,
        'platform': platform,
      },
    );
  }

  @override
  Future<void> deactivate(String installationId) async {
    await apiClient.delete(
      '$registrationPath/$installationId',
      authenticated: true,
    );
  }
}

abstract interface class PushInstallationIdStore {
  Future<String> getOrCreate();
}

/// Persists one random, non-hardware-derived UUID for this app installation.
class SecurePushInstallationIdStore implements PushInstallationIdStore {
  SecurePushInstallationIdStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'aqualogic_push_installation_id';
  final FlutterSecureStorage _storage;
  String? _installationId;
  Future<String>? _pendingRead;

  @override
  Future<String> getOrCreate() async {
    final current = _installationId;
    if (current != null) return current;

    final pending = _pendingRead;
    if (pending != null) return pending;

    final read = _readOrCreate();
    _pendingRead = read;
    try {
      return _installationId = await read;
    } finally {
      _pendingRead = null;
    }
  }

  Future<String> _readOrCreate() async {
    final saved = await _storage.read(key: _key);
    if (saved != null && _isUuid(saved)) return saved;

    final created = _randomUuidV4();
    await _storage.write(key: _key, value: created);
    return created;
  }

  bool _isUuid(String value) => RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  ).hasMatch(value);

  String _randomUuidV4() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}

typedef _RegistrationKey = ({
  String userId,
  int sessionGeneration,
  String token,
});

/// Synchronizes an available FCM token with the currently authenticated
/// backend session. Authentication and token delivery remain independent.
class PushDeviceRegistrationCoordinator {
  PushDeviceRegistrationCoordinator({
    required this.authService,
    required this.pushNotificationService,
    required this.repository,
    required this.installationIdStore,
    Duration Function(int attempt)? retryDelay,
  }) : _retryDelay = retryDelay ?? _defaultRetryDelay;

  final AuthService authService;
  final PushNotificationService pushNotificationService;
  final PushDeviceRegistrationRepository repository;
  final PushInstallationIdStore installationIdStore;
  final Duration Function(int attempt) _retryDelay;
  final Set<_RegistrationKey> _inFlight = <_RegistrationKey>{};

  StreamSubscription<String>? _tokenSubscription;
  Future<void> _operationTail = Future<void>.value();
  Timer? _retryTimer;
  _RegistrationKey? _retryKey;
  _RegistrationKey? _registeredKey;
  var _retryCount = 0;
  var _started = false;

  void start() {
    if (_started) return;
    _started = true;
    authService.addListener(_onAuthChanged);
    _tokenSubscription = pushNotificationService.tokenChanges.listen(
      (_) => _attemptRegistration(),
      onError: (Object error) => _logFailure('FCM token updates', error),
    );
    _attemptRegistration();
  }

  Future<void> deactivateCurrent() async {
    final user = authService.currentUser;
    if (!_started ||
        authService.status != AuthStatus.authenticated ||
        user == null) {
      return;
    }
    final userId = user.id;
    final sessionGeneration = authService.sessionGeneration;

    try {
      final installationId = await installationIdStore.getOrCreate();
      await _serialize(() async {
        if (!_isSameSession(userId, sessionGeneration)) return;
        await repository.deactivate(installationId);
      });
      _registeredKey = null;
    } catch (error) {
      _logFailure('Device deactivation', error);
    }
  }

  Future<void> dispose() async {
    if (!_started) return;
    _started = false;
    _retryTimer?.cancel();
    authService.removeListener(_onAuthChanged);
    await _tokenSubscription?.cancel();
    _tokenSubscription = null;
  }

  void _onAuthChanged() => _attemptRegistration();

  void _attemptRegistration() {
    if (!_started) return;
    final key = _currentKey();
    if (key == null) {
      _retryTimer?.cancel();
      _retryTimer = null;
      _retryKey = null;
      _retryCount = 0;
      _registeredKey = null;
      return;
    }

    if (_retryKey != key) {
      _retryTimer?.cancel();
      _retryTimer = null;
      _retryKey = key;
      _retryCount = 0;
    }
    if (_registeredKey == key || !_inFlight.add(key)) return;
    unawaited(_register(key));
  }

  Future<void> _register(_RegistrationKey key) async {
    try {
      await _serialize(() async {
        if (!_started || _currentKey() != key) return;
        final installationId = await installationIdStore.getOrCreate();
        if (!_started || _currentKey() != key) return;
        await repository.register(
          installationId: installationId,
          fcmToken: key.token,
          platform: 'android',
        );
        if (_currentKey() == key) _registeredKey = key;
      });

      if (_currentKey() == key && _registeredKey != key) {
        _scheduleRetry(key);
      } else if (_registeredKey == key) {
        _retryTimer?.cancel();
        _retryTimer = null;
        _retryCount = 0;
      }
    } catch (error) {
      _logFailure('Device registration', error);
      if (_currentKey() == key) _scheduleRetry(key);
    } finally {
      _inFlight.remove(key);
    }
  }

  Future<void> _serialize(Future<void> Function() operation) {
    final result = _operationTail.then((_) => operation());
    _operationTail = result.catchError((Object _) {});
    return result;
  }

  void _scheduleRetry(_RegistrationKey key) {
    _retryCount++;
    if (_retryCount >= 5 || !_started || _currentKey() != key) return;
    _retryTimer?.cancel();
    _retryTimer = Timer(_retryDelay(_retryCount), () {
      if (_currentKey() == key) _attemptRegistration();
    });
  }

  _RegistrationKey? _currentKey() {
    final user = authService.currentUser;
    final token = pushNotificationService.currentToken;
    if (authService.status != AuthStatus.authenticated ||
        user == null ||
        token == null ||
        token.isEmpty) {
      return null;
    }
    return (
      userId: user.id,
      sessionGeneration: authService.sessionGeneration,
      token: token,
    );
  }

  bool _isSameSession(String userId, int sessionGeneration) =>
      authService.status == AuthStatus.authenticated &&
      authService.currentUser?.id == userId &&
      authService.sessionGeneration == sessionGeneration;

  static Duration _defaultRetryDelay(int attempt) {
    final seconds = attempt >= 6 ? 60 : 1 << attempt;
    return Duration(seconds: seconds);
  }

  void _logFailure(String operation, Object error) {
    if (kDebugMode) {
      debugPrint('$operation unavailable (${error.runtimeType}).');
    }
  }
}

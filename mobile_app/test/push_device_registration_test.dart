import 'dart:async';
import 'dart:convert';

import 'package:aqualogic/features/auth/data/api_auth_service.dart';
import 'package:aqualogic/features/auth/data/mock_auth_service.dart';
import 'package:aqualogic/features/auth/data/refresh_credential_store.dart';
import 'package:aqualogic/features/auth/models/auth_user.dart';
import 'package:aqualogic/features/push_notifications/data/push_device_registration.dart';
import 'package:aqualogic/features/push_notifications/data/push_notification_service.dart';
import 'package:aqualogic/features/push_notifications/models/push_notification_message.dart';
import 'package:aqualogic/shared/network/api_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _MemoryCredentialStore implements RefreshCredentialStore {
  _MemoryCredentialStore([this.value]);

  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async => this.value = value;

  @override
  Future<void> delete() async => value = null;
}

class _MemoryInstallationIdStore implements PushInstallationIdStore {
  _MemoryInstallationIdStore(this.value);

  final String value;
  var readCount = 0;

  @override
  Future<String> getOrCreate() async {
    readCount++;
    return value;
  }
}

class _FakePushService implements PushNotificationService {
  _FakePushService({this.token, this.firebaseInstallationId});

  final StreamController<String> tokens = StreamController<String>.broadcast(
    sync: true,
  );
  final StreamController<String> fids = StreamController<String>.broadcast(
    sync: true,
  );
  final StreamController<PushNotificationOpenEvent> opens =
      StreamController<PushNotificationOpenEvent>.broadcast(sync: true);
  String? token;
  String? firebaseInstallationId;

  void updateToken(String value) {
    token = value;
    tokens.add(value);
  }

  void updateFid(String value) {
    firebaseInstallationId = value;
    fids.add(value);
  }

  @override
  bool get isAvailable => true;

  @override
  PushPermissionStatus get permissionStatus => PushPermissionStatus.authorized;

  @override
  String? get currentToken => token;

  @override
  String? get currentFirebaseInstallationId => firebaseInstallationId;

  @override
  Stream<String> get tokenChanges => tokens.stream;

  @override
  Stream<String> get firebaseInstallationIdChanges => fids.stream;

  @override
  Stream<PushNotificationOpenEvent> get notificationOpens => opens.stream;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> dispose() async {
    await tokens.close();
    await fids.close();
    await opens.close();
  }
}

class _Registration {
  const _Registration(
    this.installationId,
    this.firebaseInstallationId,
    this.firebaseInstallationIdRegistered,
    this.fcmToken,
    this.platform,
  );

  final String installationId;
  final String? firebaseInstallationId;
  final bool firebaseInstallationIdRegistered;
  final String? fcmToken;
  final String platform;
}

class _FakeRegistrationRepository implements PushDeviceRegistrationRepository {
  final List<_Registration> registrations = <_Registration>[];
  final Completer<void> firstSuccessfulRegistration = Completer<void>();
  var deactivations = 0;
  var failuresRemaining = 0;
  var failDeactivation = false;
  final List<String> operations = <String>[];

  @override
  Future<void> register({
    required String installationId,
    required String? firebaseInstallationId,
    required bool firebaseInstallationIdRegistered,
    required String? fcmToken,
    required String platform,
  }) async {
    operations.add('register');
    registrations.add(
      _Registration(
        installationId,
        firebaseInstallationId,
        firebaseInstallationIdRegistered,
        fcmToken,
        platform,
      ),
    );
    if (failuresRemaining > 0) {
      failuresRemaining--;
      throw StateError('Temporary registration failure');
    }
    if (!firstSuccessfulRegistration.isCompleted) {
      firstSuccessfulRegistration.complete();
    }
  }

  @override
  Future<void> deactivate(String installationId) async {
    operations.add('deactivate');
    deactivations++;
    if (failDeactivation) throw StateError('Temporary deactivation failure');
  }
}

class _AuthHarness {
  _AuthHarness(
    Future<http.Response> Function(http.Request) handler, {
    String? storedCredential,
  }) : httpClient = MockClient(handler),
       credentialStore = _MemoryCredentialStore(storedCredential) {
    apiClient = ApiClient(
      baseUrl: 'https://api.example.test',
      httpClient: httpClient,
    );
    auth = ApiAuthService(
      apiClient: apiClient,
      credentialStore: credentialStore,
    );
  }

  final MockClient httpClient;
  final _MemoryCredentialStore credentialStore;
  late final ApiClient apiClient;
  late final ApiAuthService auth;

  void dispose() {
    auth.dispose();
    httpClient.close();
  }
}

Map<String, Object?> _userJson() => <String, Object?>{
  'id': 27,
  'name': 'Aqua User',
  'email': 'aqua@example.test',
  'role': 'admin',
  'is_active': true,
  'must_change_password': false,
  'created_at': '2026-09-20T10:00:00Z',
};

Map<String, Object?> _tokenJson({String accessToken = 'access-token'}) =>
    <String, Object?>{
      'access_token': accessToken,
      'token_type': 'bearer',
      'expires_at': DateTime.now()
          .toUtc()
          .add(const Duration(minutes: 15))
          .toIso8601String(),
      'must_change_password': false,
      'user': _userJson(),
    };

http.Response _response(
  int status,
  Object? body, {
  Map<String, String> headers = const {},
}) => http.Response(
  body == null ? '' : jsonEncode(body),
  status,
  headers: <String, String>{'content-type': 'application/json', ...headers},
);

http.Response _tokenResponse({String cookie = 'refresh-token'}) => _response(
  200,
  _tokenJson(),
  headers: <String, String>{
    'set-cookie': 'aqualogic_refresh=$cookie; HttpOnly; Path=/',
  },
);

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  final harnesses = <_AuthHarness>[];
  final pushServices = <_FakePushService>[];
  final coordinators = <PushDeviceRegistrationCoordinator>[];

  setUp(() {
    harnesses.clear();
    pushServices.clear();
    coordinators.clear();
  });

  tearDown(() async {
    for (final coordinator in coordinators) {
      await coordinator.dispose();
    }
    for (final push in pushServices) {
      await push.dispose();
    }
    for (final value in harnesses) {
      value.dispose();
    }
  });

  _AuthHarness harness(
    Future<http.Response> Function(http.Request) handler, {
    String? storedCredential,
  }) {
    final value = _AuthHarness(handler, storedCredential: storedCredential);
    harnesses.add(value);
    return value;
  }

  _FakePushService push({String? token, String? firebaseInstallationId}) {
    final value = _FakePushService(
      token: token,
      firebaseInstallationId: firebaseInstallationId,
    );
    pushServices.add(value);
    return value;
  }

  PushDeviceRegistrationCoordinator coordinator({
    required ApiAuthService auth,
    required _FakePushService push,
    required _FakeRegistrationRepository repository,
    Duration Function(int attempt)? retryDelay,
  }) {
    final value = PushDeviceRegistrationCoordinator(
      authService: auth,
      pushNotificationService: push,
      repository: repository,
      installationIdStore: _MemoryInstallationIdStore(
        '11111111-1111-4111-8111-111111111111',
      ),
      retryDelay: retryDelay,
    );
    coordinators.add(value);
    value.start();
    return value;
  }

  test('cold auth restore registers the initial FCM token once', () async {
    final value = harness((request) async {
      if (request.url.path == ApiAuthService.refreshPath) {
        return _tokenResponse(cookie: 'stored-refresh');
      }
      if (request.url.path == ApiAuthService.currentUserPath) {
        return _response(200, _userJson());
      }
      return _response(404, <String, Object?>{'detail': 'not found'});
    }, storedCredential: 'stored-refresh');
    final fakePush = push(token: 'initial-fcm-token');
    final repository = _FakeRegistrationRepository();
    coordinator(auth: value.auth, push: fakePush, repository: repository);

    await value.auth.initialize();
    await _settle();

    expect(value.auth.status, AuthStatus.authenticated);
    expect(repository.registrations, hasLength(1));
    expect(
      repository.registrations.single.installationId,
      '11111111-1111-4111-8111-111111111111',
    );
    expect(repository.registrations.single.fcmToken, 'initial-fcm-token');
    expect(repository.registrations.single.platform, 'android');
  });

  test('a token that becomes available after login is registered', () async {
    final value = harness((request) async {
      if (request.url.path == ApiAuthService.loginPath) return _tokenResponse();
      return _response(404, <String, Object?>{'detail': 'not found'});
    });
    final fakePush = push();
    final repository = _FakeRegistrationRepository();
    coordinator(auth: value.auth, push: fakePush, repository: repository);

    await value.auth.signIn(
      email: 'aqua@example.test',
      password: 'not-logged-or-exposed',
    );
    await _settle();
    expect(repository.registrations, isEmpty);

    fakePush.updateToken('late-fcm-token');
    await _settle();

    expect(repository.registrations, hasLength(1));
    expect(repository.registrations.single.fcmToken, 'late-fcm-token');
  });

  test('a FID-registered installation can register without an FCM token', () async {
    final value = harness((request) async {
      if (request.url.path == ApiAuthService.loginPath) return _tokenResponse();
      return _response(404, <String, Object?>{'detail': 'not found'});
    });
    final fakePush = push(firebaseInstallationId: 'registered-fid');
    final repository = _FakeRegistrationRepository();
    coordinator(auth: value.auth, push: fakePush, repository: repository);

    await value.auth.signIn(email: 'aqua@example.test', password: 'password');
    await _settle();

    expect(repository.registrations, hasLength(1));
    expect(repository.registrations.single.firebaseInstallationId, 'registered-fid');
    expect(repository.registrations.single.firebaseInstallationIdRegistered, isTrue);
    expect(repository.registrations.single.fcmToken, isNull);
  });

  test('FCM token refresh uses the same installation registration', () async {
    final value = harness((request) async {
      if (request.url.path == ApiAuthService.loginPath) return _tokenResponse();
      return _response(404, <String, Object?>{'detail': 'not found'});
    });
    final fakePush = push(token: 'fcm-token-before-refresh');
    final repository = _FakeRegistrationRepository();
    coordinator(auth: value.auth, push: fakePush, repository: repository);

    await value.auth.signIn(email: 'aqua@example.test', password: 'password');
    await _settle();
    fakePush.updateToken('fcm-token-after-refresh');
    await _settle();

    expect(repository.registrations, hasLength(2));
    expect(
      repository.registrations[0].installationId,
      repository.registrations[1].installationId,
    );
    expect(repository.registrations[1].fcmToken, 'fcm-token-after-refresh');
  });

  test(
    'Firebase Installation ID changes re-register the same FCM token',
    () async {
      final value = harness((request) async {
        if (request.url.path == ApiAuthService.loginPath) {
          return _tokenResponse();
        }
        return _response(404, <String, Object?>{'detail': 'not found'});
      });
      final fakePush = push(
        token: 'stable-fcm-registration-token',
        firebaseInstallationId: 'old-firebase-installation-id',
      );
      final repository = _FakeRegistrationRepository();
      coordinator(auth: value.auth, push: fakePush, repository: repository);

      await value.auth.signIn(email: 'aqua@example.test', password: 'password');
      await _settle();
      fakePush.updateFid('new-firebase-installation-id');
      await _settle();

      expect(repository.registrations, hasLength(2));
      expect(
        repository.registrations.map((row) => row.firebaseInstallationId),
        <String?>[
          'old-firebase-installation-id',
          'new-firebase-installation-id',
        ],
      );
      expect(repository.registrations.map((row) => row.fcmToken), <String>[
        'stable-fcm-registration-token',
        'stable-fcm-registration-token',
      ]);
      expect(
        repository.registrations.map(
          (row) => row.firebaseInstallationIdRegistered,
        ),
        <bool>[true, true],
      );
    },
  );

  test(
    'registration retries transient failures without changing auth state',
    () async {
      final value = harness((request) async {
        if (request.url.path == ApiAuthService.loginPath) {
          return _tokenResponse();
        }
        return _response(404, <String, Object?>{'detail': 'not found'});
      });
      final fakePush = push(token: 'retryable-fcm-token');
      final repository = _FakeRegistrationRepository()..failuresRemaining = 1;
      coordinator(
        auth: value.auth,
        push: fakePush,
        repository: repository,
        retryDelay: (_) => Duration.zero,
      );

      final user = await value.auth.signIn(
        email: 'aqua@example.test',
        password: 'password',
      );
      await repository.firstSuccessfulRegistration.future.timeout(
        const Duration(seconds: 5),
      );

      expect(user, isA<AuthUser>());
      expect(value.auth.status, AuthStatus.authenticated);
      expect(repository.registrations, hasLength(2));
    },
  );

  test(
    'new authentication session re-registers the same installation',
    () async {
      final value = harness((request) async {
        if (request.url.path == ApiAuthService.loginPath) {
          return _tokenResponse();
        }
        if (request.url.path == ApiAuthService.logoutPath) {
          return _response(204, null);
        }
        return _response(404, <String, Object?>{'detail': 'not found'});
      });
      final fakePush = push(token: 'persistent-fcm-token');
      final repository = _FakeRegistrationRepository();
      coordinator(auth: value.auth, push: fakePush, repository: repository);

      await value.auth.signIn(email: 'aqua@example.test', password: 'password');
      await _settle();
      final firstGeneration = value.auth.sessionGeneration;
      await value.auth.signOut();
      await value.auth.signIn(email: 'aqua@example.test', password: 'password');
      await _settle();

      expect(value.auth.sessionGeneration, greaterThan(firstGeneration));
      expect(repository.registrations, hasLength(2));
      expect(
        repository.registrations[0].installationId,
        repository.registrations[1].installationId,
      );
    },
  );

  test('best-effort deactivation failure does not prevent logout', () async {
    final value = harness((request) async {
      if (request.url.path == ApiAuthService.loginPath) {
        return _tokenResponse();
      }
      if (request.url.path == ApiAuthService.logoutPath) {
        return _response(204, null);
      }
      return _response(404, <String, Object?>{'detail': 'not found'});
    });
    final fakePush = push(token: 'logout-fcm-token');
    final repository = _FakeRegistrationRepository()..failDeactivation = true;
    final registration = coordinator(
      auth: value.auth,
      push: fakePush,
      repository: repository,
    );
    value.auth.setBeforeSignOutHook(registration.deactivateCurrent);
    await value.auth.signIn(email: 'aqua@example.test', password: 'password');
    await _settle();

    await value.auth.signOut();

    expect(repository.deactivations, 1);
    expect(
      repository.operations.indexOf('deactivate'),
      greaterThanOrEqualTo(0),
    );
    expect(value.auth.status, AuthStatus.unauthenticated);
  });

  test(
    'registration API sends the token only in the authenticated request',
    () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        return _response(204, null);
      });
      final api = ApiClient(
        baseUrl: 'https://api.example.test',
        httpClient: client,
      );
      api.configureAuthentication(
        accessTokenReader: () => 'access-value',
        accessTokenExpiryReader: () =>
            DateTime.now().add(const Duration(minutes: 5)),
        refreshAccessToken: () async => false,
      );
      final repository = ApiPushDeviceRegistrationRepository(apiClient: api);

      await repository.register(
        installationId: '11111111-1111-4111-8111-111111111111',
        firebaseInstallationId: 'distinct-firebase-installation-id',
        firebaseInstallationIdRegistered: true,
        fcmToken: 'private-fcm-token',
        platform: 'android',
      );
      await repository.deactivate('11111111-1111-4111-8111-111111111111');

      expect(requests[0].method, 'PUT');
      expect(requests[0].headers['authorization'], 'Bearer access-value');
      expect(jsonDecode(requests[0].body), <String, Object?>{
        'installation_id': '11111111-1111-4111-8111-111111111111',
        'firebase_installation_id': 'distinct-firebase-installation-id',
        'firebase_installation_id_registered': true,
        'fcm_token': 'private-fcm-token',
        'platform': 'android',
      });
      expect(requests[1].method, 'DELETE');
      expect(
        requests[1].url.path,
        endsWith('/current/11111111-1111-4111-8111-111111111111'),
      );
      api.close();
      client.close();
    },
  );

  test(
    'device-registration debug failures never include the FCM token',
    () async {
      final value = harness((request) async {
        if (request.url.path == ApiAuthService.loginPath) {
          return _tokenResponse();
        }
        return _response(404, <String, Object?>{'detail': 'not found'});
      });
      const token = 'full-secret-fcm-token-for-log-check';
      const fid = 'full-secret-firebase-installation-id-for-log-check';
      final fakePush = push(token: token, firebaseInstallationId: fid);
      final repository = _FakeRegistrationRepository()..failuresRemaining = 1;
      final messages = <String>[];
      final previousDebugPrint = debugPrint;
      debugPrint = (message, {wrapWidth}) => messages.add(message ?? '');
      addTearDown(() => debugPrint = previousDebugPrint);
      coordinator(
        auth: value.auth,
        push: fakePush,
        repository: repository,
        retryDelay: (_) => const Duration(days: 1),
      );

      await value.auth.signIn(email: 'aqua@example.test', password: 'password');
      await _settle();

      expect(messages.join('\n'), isNot(contains(token)));
      expect(messages.join('\n'), isNot(contains(fid)));
    },
  );
}

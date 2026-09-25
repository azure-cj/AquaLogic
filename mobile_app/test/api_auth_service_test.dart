import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aqualogic/app/auth/auth_gate.dart';
import 'package:aqualogic/app/auth/auth_scope.dart';
import 'package:aqualogic/features/auth/data/api_auth_service.dart';
import 'package:aqualogic/features/auth/data/mock_auth_service.dart';
import 'package:aqualogic/features/auth/data/refresh_credential_store.dart';
import 'package:aqualogic/features/auth/models/user_role.dart';
import 'package:aqualogic/features/auth/screens/password_change_screen.dart';
import 'package:aqualogic/shared/network/api_client.dart';
import 'package:aqualogic/shared/network/api_failure.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _MemoryCredentialStore implements RefreshCredentialStore {
  _MemoryCredentialStore([this.value]);

  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async {
    this.value = value;
  }

  @override
  Future<void> delete() async {
    value = null;
  }
}

class _Harness {
  _Harness(
    Future<http.Response> Function(http.Request) handler, {
    String? storedCredential,
  }) : httpClient = MockClient(handler),
       store = _MemoryCredentialStore(storedCredential) {
    apiClient = ApiClient(
      baseUrl: 'https://api.example.test',
      httpClient: httpClient,
    );
    auth = ApiAuthService(apiClient: apiClient, credentialStore: store);
  }

  final MockClient httpClient;
  final _MemoryCredentialStore store;
  late final ApiClient apiClient;
  late final ApiAuthService auth;

  void dispose() {
    auth.dispose();
    httpClient.close();
  }
}

final _futureExpiry = DateTime.utc(2030, 1, 1).toIso8601String();

Map<String, Object?> _tokenJson({
  String accessToken = 'access-one',
  String role = 'admin',
  bool mustChangePassword = false,
  String? expiresAt,
}) => {
  'access_token': accessToken,
  'token_type': 'bearer',
  'expires_at': expiresAt ?? _futureExpiry,
  'must_change_password': mustChangePassword,
  'user': _userJson(role: role, mustChangePassword: mustChangePassword),
};

Map<String, Object?> _userJson({
  String role = 'admin',
  bool mustChangePassword = false,
}) => {
  'id': 27,
  'name': 'Aqua User',
  'email': 'aqua@example.test',
  'role': role,
  'is_active': true,
  'must_change_password': mustChangePassword,
  'created_at': '2026-09-20T10:00:00Z',
};

http.Response _response(
  int status,
  Object? body, {
  Map<String, String> headers = const {},
}) => http.Response(
  body == null ? '' : jsonEncode(body),
  status,
  headers: {'content-type': 'application/json', ...headers},
);

http.Response _tokenResponse({
  String accessToken = 'access-one',
  String role = 'admin',
  bool mustChangePassword = false,
  String? cookie = 'refresh-one',
  String? expiresAt,
}) => _response(
  200,
  _tokenJson(
    accessToken: accessToken,
    role: role,
    mustChangePassword: mustChangePassword,
    expiresAt: expiresAt,
  ),
  headers: cookie == null
      ? const {}
      : {'set-cookie': 'aqualogic_refresh=$cookie; HttpOnly; Path=/'},
);

Future<void> _login(ApiAuthService service) async {
  await service.signIn(email: 'aqua@example.test', password: 'fake-password');
}

void main() {
  final harnesses = <_Harness>[];
  setUp(() => harnesses.clear());
  tearDown(() {
    for (final harness in harnesses) {
      harness.dispose();
    }
  });

  _Harness harness(
    Future<http.Response> Function(http.Request) handler, {
    String? storedCredential,
  }) {
    final value = _Harness(handler, storedCredential: storedCredential);
    harnesses.add(value);
    return value;
  }

  test(
    'login stores the refresh cookie and maps the server identity',
    () async {
      final value = harness((request) async {
        if (request.url.path == ApiAuthService.loginPath) {
          expect(jsonDecode(request.body), {
            'email': 'aqua@example.test',
            'password': 'fake-password',
          });
          return _tokenResponse();
        }
        if (request.url.path == ApiAuthService.currentUserPath) {
          expect(request.headers['authorization'], 'Bearer access-one');
          return _response(200, _userJson());
        }
        return _response(404, {'detail': 'not found'});
      });

      final user = await value.auth.signIn(
        email: ' aqua@example.test ',
        password: 'fake-password',
      );
      expect(value.auth.status, AuthStatus.authenticated);
      expect(user?.id, '27');
      expect(user?.role, UserRole.admin);
      expect(user?.roleLabel, 'Owner');
      expect(value.store.value, 'refresh-one');

      await value.apiClient.get(
        ApiAuthService.currentUserPath,
        authenticated: true,
      );
    },
  );

  test('401 login remains unauthenticated with a safe failure', () async {
    final value = harness((request) async {
      if (request.url.path == ApiAuthService.refreshPath ||
          request.url.path == ApiAuthService.loginPath) {
        return _response(401, {'detail': 'sensitive backend detail'});
      }
      return _response(404, {'detail': 'not found'});
    });
    await value.auth.initialize();

    await expectLater(
      value.auth.signIn(email: 'wrong@example.test', password: 'not-valid'),
      throwsA(
        isA<ApiFailure>()
            .having(
              (failure) => failure.kind,
              'kind',
              ApiFailureKind.unauthenticated,
            )
            .having(
              (failure) => failure.message,
              'message',
              'Your sign-in session has expired.',
            ),
      ),
    );
    expect(value.auth.status, AuthStatus.unauthenticated);
    expect(value.store.value, isNull);
  });

  test(
    '429 login retains Retry-After without exposing server detail',
    () async {
      final value = harness(
        (_) async => _response(
          429,
          {'detail': 'throttle payload'},
          headers: {'retry-after': '90'},
        ),
      );

      try {
        await value.auth.signIn(email: 'aqua@example.test', password: 'fake');
        fail('Expected rate limit failure.');
      } on ApiFailure catch (failure) {
        expect(failure.kind, ApiFailureKind.rateLimited);
        expect(failure.retryAfter, const Duration(seconds: 90));
        expect(failure.message, 'Too many requests. Try again shortly.');
      }
    },
  );

  test('cold restore rotates cookie and hydrates /auth/me identity', () async {
    final value = harness((request) async {
      if (request.url.path == ApiAuthService.refreshPath) {
        expect(request.headers['cookie'], 'aqualogic_refresh=refresh-old');
        return _tokenResponse(
          accessToken: 'access-restored',
          cookie: 'refresh-new',
        );
      }
      if (request.url.path == ApiAuthService.currentUserPath) {
        expect(request.headers['authorization'], 'Bearer access-restored');
        return _response(200, _userJson(role: 'staff'));
      }
      return _response(404, {'detail': 'not found'});
    }, storedCredential: 'refresh-old');

    await value.auth.initialize();
    expect(value.auth.status, AuthStatus.authenticated);
    expect(value.auth.currentUser?.role, UserRole.staff);
    expect(value.auth.currentUser?.roleLabel, 'Staff');
    expect(value.store.value, 'refresh-new');
  });

  test(
    'invalid refresh clears the credential and returns to Login state',
    () async {
      final value = harness(
        (_) async => _response(
          401,
          {'detail': 'revoked'},
          headers: {'set-cookie': 'aqualogic_refresh=""; Max-Age=0; Path=/'},
        ),
        storedCredential: 'revoked-refresh',
      );

      await value.auth.initialize();
      expect(value.auth.status, AuthStatus.unauthenticated);
      expect(value.auth.currentUser, isNull);
      expect(value.store.value, isNull);
    },
  );

  test('startup network failure keeps refresh credential for retry', () async {
    final value = harness(
      (_) async => throw const SocketException('simulated offline'),
      storedCredential: 'refresh-retained',
    );

    await value.auth.initialize();
    expect(value.auth.status, AuthStatus.connectionUnavailable);
    expect(value.store.value, 'refresh-retained');
  });

  testWidgets('startup connection state provides a working retry action', (
    tester,
  ) async {
    final value = harness(
      (_) async => throw const SocketException('simulated offline'),
      storedCredential: 'refresh-retained',
    );
    await value.auth.initialize();

    await tester.pumpWidget(
      MaterialApp(
        home: AuthScope(authService: value.auth, child: const AuthGate()),
      ),
    );
    expect(find.text("Couldn't connect to AquaLogic"), findsOneWidget);
    expect(find.byKey(const ValueKey('auth-startup-retry')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('auth-startup-retry')));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't connect to AquaLogic"), findsOneWidget);
    expect(value.store.value, 'refresh-retained');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test(
    'refresh grace response without a new cookie keeps the old value',
    () async {
      final value = harness((request) async {
        if (request.url.path == ApiAuthService.refreshPath) {
          return _tokenResponse(accessToken: 'access-grace', cookie: null);
        }
        if (request.url.path == ApiAuthService.currentUserPath) {
          return _response(200, _userJson());
        }
        return _response(404, {'detail': 'not found'});
      }, storedCredential: 'refresh-grace');

      await value.auth.initialize();
      expect(value.auth.status, AuthStatus.authenticated);
      expect(value.store.value, 'refresh-grace');
    },
  );

  test(
    'one expired-access 401 refreshes once and retries the request',
    () async {
      var protectedCalls = 0;
      var refreshCalls = 0;
      final value = harness((request) async {
        if (request.url.path == ApiAuthService.loginPath) {
          return _tokenResponse();
        }
        if (request.url.path == ApiAuthService.refreshPath) {
          refreshCalls++;
          expect(request.headers['cookie'], 'aqualogic_refresh=refresh-one');
          return _tokenResponse(
            accessToken: 'access-two',
            cookie: 'refresh-two',
          );
        }
        if (request.url.path == '/protected') {
          protectedCalls++;
          if (request.headers['authorization'] == 'Bearer access-one') {
            return _response(401, {'detail': 'expired'});
          }
          expect(request.headers['authorization'], 'Bearer access-two');
          return _response(200, {'ok': true});
        }
        return _response(404, {'detail': 'not found'});
      });
      await _login(value.auth);

      final response = await value.apiClient.get(
        '/protected',
        authenticated: true,
      );
      expect(response.body, {'ok': true});
      expect(protectedCalls, 2);
      expect(refreshCalls, 1);
      expect(value.store.value, 'refresh-two');
    },
  );

  test(
    'backend expires_at triggers refresh before the protected request',
    () async {
      var protectedCalls = 0;
      var refreshCalls = 0;
      final value = harness((request) async {
        if (request.url.path == ApiAuthService.loginPath) {
          return _tokenResponse(
            expiresAt: DateTime.now()
                .toUtc()
                .subtract(const Duration(minutes: 1))
                .toIso8601String(),
          );
        }
        if (request.url.path == ApiAuthService.refreshPath) {
          refreshCalls++;
          return _tokenResponse(
            accessToken: 'access-after-expiry',
            cookie: 'refresh-after-expiry',
          );
        }
        if (request.url.path == '/protected') {
          protectedCalls++;
          expect(
            request.headers['authorization'],
            'Bearer access-after-expiry',
          );
          return _response(200, {'ok': true});
        }
        return _response(404, {'detail': 'not found'});
      });
      await _login(value.auth);

      await value.apiClient.get('/protected', authenticated: true);
      expect(refreshCalls, 1);
      expect(protectedCalls, 1);
    },
  );

  test('simultaneous 401 responses share one refresh operation', () async {
    final refreshStarted = Completer<void>();
    final releaseRefresh = Completer<void>();
    var refreshCalls = 0;
    var initialRequests = 0;
    final value = harness((request) async {
      if (request.url.path == ApiAuthService.loginPath) {
        return _tokenResponse();
      }
      if (request.url.path == ApiAuthService.refreshPath) {
        refreshCalls++;
        if (!refreshStarted.isCompleted) refreshStarted.complete();
        await releaseRefresh.future;
        return _tokenResponse(accessToken: 'access-two', cookie: 'refresh-two');
      }
      if (request.url.path == '/one' || request.url.path == '/two') {
        if (request.headers['authorization'] == 'Bearer access-one') {
          initialRequests++;
          return _response(401, {'detail': 'expired'});
        }
        return _response(200, {'ok': true});
      }
      return _response(404, {'detail': 'not found'});
    });
    await _login(value.auth);

    final requests = Future.wait([
      value.apiClient.get('/one', authenticated: true),
      value.apiClient.get('/two', authenticated: true),
    ]);
    await refreshStarted.future;
    await Future<void>.delayed(Duration.zero);
    expect(initialRequests, 2);
    expect(refreshCalls, 1);
    releaseRefresh.complete();

    final responses = await requests;
    expect(responses.map((response) => response.body), [
      {'ok': true},
      {'ok': true},
    ]);
    expect(refreshCalls, 1);
  });

  test(
    'unknown backend role is rejected and never mapped to Owner or Staff',
    () async {
      var logoutCalls = 0;
      final value = harness((request) async {
        if (request.url.path == ApiAuthService.loginPath) {
          return _tokenResponse(role: 'owner');
        }
        if (request.url.path == ApiAuthService.logoutPath) {
          logoutCalls++;
          return _response(200, {'message': 'ok'});
        }
        return _response(404, {'detail': 'not found'});
      });

      await expectLater(
        value.auth.signIn(email: 'aqua@example.test', password: 'fake'),
        throwsA(isA<ApiFailure>()),
      );
      expect(value.auth.status, AuthStatus.unauthenticated);
      expect(value.auth.currentUser, isNull);
      expect(value.store.value, isNull);
      expect(logoutCalls, 1);
    },
  );

  testWidgets('forced password state never enters the authenticated shell', (
    tester,
  ) async {
    final value = harness((request) async {
      if (request.url.path == ApiAuthService.loginPath) {
        return _tokenResponse(mustChangePassword: true);
      }
      return _response(404, {'detail': 'not found'});
    });
    await _login(value.auth);
    await tester.pumpWidget(
      MaterialApp(
        home: AuthScope(authService: value.auth, child: const AuthGate()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(PasswordChangeScreen), findsOneWidget);
    expect(find.text('Set a new password'), findsOneWidget);
    expect(find.text('Home'), findsNothing);
  });

  test('password change installs the new access and refresh session', () async {
    final value = harness((request) async {
      if (request.url.path == ApiAuthService.loginPath) {
        return _tokenResponse(mustChangePassword: true);
      }
      if (request.url.path == ApiAuthService.changePasswordPath) {
        expect(request.headers['authorization'], 'Bearer access-one');
        expect(jsonDecode(request.body), {
          'current_password': 'fake-current',
          'new_password': 'fake-new-password-12',
        });
        return _tokenResponse(
          accessToken: 'access-after-change',
          mustChangePassword: false,
          cookie: 'refresh-after-change',
        );
      }
      return _response(404, {'detail': 'not found'});
    });
    await _login(value.auth);

    await value.auth.changePassword(
      currentPassword: 'fake-current',
      newPassword: 'fake-new-password-12',
    );
    expect(value.auth.status, AuthStatus.authenticated);
    expect(value.auth.currentUser?.mustChangePassword, isFalse);
    expect(value.store.value, 'refresh-after-change');
  });

  test('logout revokes remotely then clears the local session', () async {
    var logoutCalls = 0;
    final value = harness((request) async {
      if (request.url.path == ApiAuthService.loginPath) {
        return _tokenResponse();
      }
      if (request.url.path == ApiAuthService.logoutPath) {
        logoutCalls++;
        expect(request.headers['authorization'], 'Bearer access-one');
        return _response(200, {'message': 'Logged out'});
      }
      return _response(404, {'detail': 'not found'});
    });
    await _login(value.auth);

    await value.auth.signOut();
    expect(logoutCalls, 1);
    expect(value.auth.status, AuthStatus.unauthenticated);
    expect(value.auth.currentUser, isNull);
    expect(value.store.value, isNull);
  });

  test('offline logout still clears the local session', () async {
    final value = harness((request) async {
      if (request.url.path == ApiAuthService.loginPath) {
        return _tokenResponse();
      }
      if (request.url.path == ApiAuthService.logoutPath) {
        throw const SocketException('offline');
      }
      return _response(404, {'detail': 'not found'});
    });
    await _login(value.auth);

    await value.auth.signOut();
    expect(value.auth.status, AuthStatus.unauthenticated);
    expect(value.auth.currentUser, isNull);
    expect(value.store.value, isNull);
  });
}

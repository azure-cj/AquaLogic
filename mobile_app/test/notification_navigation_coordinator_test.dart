import 'dart:async';

import 'package:aqualogic/features/auth/data/mock_auth_service.dart';
import 'package:aqualogic/features/auth/models/auth_user.dart';
import 'package:aqualogic/features/push_notifications/data/notification_navigation_coordinator.dart';
import 'package:aqualogic/features/push_notifications/data/push_notification_service.dart';
import 'package:aqualogic/features/push_notifications/models/push_notification_intent.dart';
import 'package:aqualogic/features/push_notifications/models/push_notification_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'parses supported string-only event payloads and verifies event keys',
    () {
      final cases =
          <(Map<String, Object?>, PushNotificationIntentKind, String)>[
            (
              _payload(
                type: 'water_quality_alert',
                eventKey: 'water_quality_alert:42:created',
                recordKey: 'alert_id',
                recordId: '42',
              ),
              PushNotificationIntentKind.waterQualityAlert,
              '42',
            ),
            (
              _payload(
                type: 'monitoring_incident',
                eventKey: 'monitoring_incident:43:opened',
                recordKey: 'incident_id',
                recordId: '43',
              ),
              PushNotificationIntentKind.monitoringIncident,
              '43',
            ),
            (
              _payload(
                type: 'monitoring_recovered',
                eventKey: 'monitoring_incident:44:recovered',
                recordKey: 'incident_id',
                recordId: '44',
              ),
              PushNotificationIntentKind.monitoringRecovered,
              '44',
            ),
          ];

      for (final (data, kind, recordId) in cases) {
        final intent = PushNotificationIntent.parse(
          PushNotificationOpenEvent(data: data),
        );
        expect(intent?.kind, kind);
        expect(intent?.recordId, recordId);
        expect(intent?.tankId, '8');
      }

      final mismatchedKey = _payload(
        type: 'water_quality_alert',
        eventKey: 'monitoring_incident:42:opened',
        recordKey: 'alert_id',
        recordId: '42',
      );
      expect(
        PushNotificationIntent.parse(
          PushNotificationOpenEvent(data: mismatchedKey),
        ),
        isNull,
      );
    },
  );

  test(
    'cold-start intent waits for restored authentication and shell readiness',
    () async {
      final auth = _FakeAuthService(AuthStatus.checking);
      final push = _FakePushNotificationService(
        initialOpen: _openEvent('water_quality_alert', '42'),
      );
      final navigations = <PushNotificationIntent?>[];
      final coordinator = NotificationNavigationCoordinator(
        authService: auth,
        pushNotificationService: push,
        navigate: (intent) {
          navigations.add(intent);
          return true;
        },
      )..start();

      await push.initialize();
      auth.setStatus(AuthStatus.unauthenticated);
      coordinator.onAuthenticatedShellReady();
      expect(navigations, isEmpty);

      auth.setStatus(AuthStatus.authenticated);
      expect(navigations, isEmpty);
      coordinator.onAuthenticatedShellReady();
      await Future<void>.delayed(Duration.zero);

      expect(navigations, hasLength(1));
      expect(navigations.single?.recordId, '42');
      await coordinator.dispose();
      await push.dispose();
      auth.dispose();
    },
  );

  test('password-change requirement keeps the pending intent gated', () async {
    final auth = _FakeAuthService(AuthStatus.mustChangePassword);
    final push = _FakePushNotificationService();
    final navigations = <PushNotificationIntent?>[];
    final coordinator = NotificationNavigationCoordinator(
      authService: auth,
      pushNotificationService: push,
      navigate: (intent) {
        navigations.add(intent);
        return true;
      },
    )..start();

    push.opens.add(_openEvent('monitoring_recovered', '71'));
    coordinator.onAuthenticatedShellReady();
    expect(navigations, isEmpty);

    auth.setStatus(AuthStatus.authenticated);
    coordinator.onAuthenticatedShellReady();
    await Future<void>.delayed(Duration.zero);
    expect(
      navigations.single?.kind,
      PushNotificationIntentKind.monitoringRecovered,
    );
    expect(navigations.single?.recordId, '71');
    await coordinator.dispose();
    await push.dispose();
    auth.dispose();
  });

  test(
    'one pending slot keeps the latest tap and duplicate event keys navigate once',
    () async {
      final auth = _FakeAuthService(AuthStatus.unauthenticated);
      final push = _FakePushNotificationService();
      final navigations = <PushNotificationIntent?>[];
      final coordinator = NotificationNavigationCoordinator(
        authService: auth,
        pushNotificationService: push,
        navigate: (intent) {
          navigations.add(intent);
          return true;
        },
      )..start();

      push.opens.add(_openEvent('water_quality_alert', '42'));
      push.opens.add(_openEvent('monitoring_incident', '73'));
      auth.setStatus(AuthStatus.authenticated);
      coordinator.onAuthenticatedShellReady();
      await Future<void>.delayed(Duration.zero);
      push.opens.add(_openEvent('monitoring_incident', '73'));
      await Future<void>.delayed(Duration.zero);

      expect(navigations, hasLength(1));
      expect(
        navigations.single?.kind,
        PushNotificationIntentKind.monitoringIncident,
      );
      expect(navigations.single?.recordId, '73');
      await coordinator.dispose();
      await push.dispose();
      auth.dispose();
    },
  );

  test(
    'unknown and malformed payloads safely request the Alerts fallback',
    () async {
      final invalidEvents = <PushNotificationOpenEvent>[
        PushNotificationOpenEvent(
          data: _payload(
            type: 'future_type',
            eventKey: 'future_type:1:created',
            recordKey: 'alert_id',
            recordId: '1',
          ),
        ),
        PushNotificationOpenEvent(
          data: const <String, Object?>{
            'schema_version': '1',
            'type': 'water_quality_alert',
            'event_key': 'water_quality_alert:1:created',
            'tank_id': '8',
          },
        ),
        PushNotificationOpenEvent(
          data: _payload(
            type: 'monitoring_incident',
            eventKey: 'monitoring_incident:bad:opened',
            recordKey: 'incident_id',
            recordId: 'bad',
          ),
        ),
        PushNotificationOpenEvent(
          data: <String, Object?>{
            ..._payload(
              type: 'water_quality_alert',
              eventKey: 'water_quality_alert:1:created',
              recordKey: 'alert_id',
              recordId: '1',
            ),
            'unexpected': 1,
          },
        ),
      ];

      for (var index = 0; index < invalidEvents.length; index++) {
        final auth = _FakeAuthService(AuthStatus.authenticated);
        final push = _FakePushNotificationService();
        final navigations = <PushNotificationIntent?>[];
        final coordinator = NotificationNavigationCoordinator(
          authService: auth,
          pushNotificationService: push,
          navigate: (intent) {
            navigations.add(intent);
            return true;
          },
        )..start();
        coordinator.onAuthenticatedShellReady();
        push.opens.add(invalidEvents[index]);
        await Future<void>.delayed(Duration.zero);

        expect(navigations, [null]);
        await coordinator.dispose();
        await push.dispose();
        auth.dispose();
      }
    },
  );

  test('duplicate callback message IDs navigate only once', () async {
    final auth = _FakeAuthService(AuthStatus.authenticated);
    final push = _FakePushNotificationService();
    final navigations = <PushNotificationIntent?>[];
    final coordinator = NotificationNavigationCoordinator(
      authService: auth,
      pushNotificationService: push,
      navigate: (intent) {
        navigations.add(intent);
        return true;
      },
    )..start();
    coordinator.onAuthenticatedShellReady();

    final duplicate = PushNotificationOpenEvent(
      messageId: 'same-firebase-message',
      data: const <String, Object?>{'type': 'unknown_future_type'},
    );
    push.opens.add(duplicate);
    push.opens.add(duplicate);
    await Future<void>.delayed(Duration.zero);

    expect(navigations, [null]);
    await coordinator.dispose();
    await push.dispose();
    auth.dispose();
  });

  test(
    'navigation callback failure falls back without replaying the payload',
    () async {
      final auth = _FakeAuthService(AuthStatus.authenticated);
      final push = _FakePushNotificationService();
      final attempts = <PushNotificationIntent?>[];
      final coordinator = NotificationNavigationCoordinator(
        authService: auth,
        pushNotificationService: push,
        navigate: (intent) {
          attempts.add(intent);
          if (intent != null) throw StateError('navigation failed');
          return true;
        },
      )..start();
      coordinator.onAuthenticatedShellReady();

      push.opens.add(_openEvent('water_quality_alert', '42'));
      await Future<void>.delayed(Duration.zero);

      expect(attempts, hasLength(2));
      expect(attempts.first?.recordId, '42');
      expect(attempts.last, isNull);
      await coordinator.dispose();
      await push.dispose();
      auth.dispose();
    },
  );
}

Map<String, Object?> _payload({
  required String type,
  required String eventKey,
  required String recordKey,
  required String recordId,
}) => <String, Object?>{
  'schema_version': '1',
  'type': type,
  'event_key': eventKey,
  'tank_id': '8',
  recordKey: recordId,
};

PushNotificationOpenEvent _openEvent(String type, String recordId) {
  final isAlert = type == 'water_quality_alert';
  final isRecovery = type == 'monitoring_recovered';
  final recordKey = isAlert ? 'alert_id' : 'incident_id';
  final eventKey = isAlert
      ? 'water_quality_alert:$recordId:created'
      : 'monitoring_incident:$recordId:${isRecovery ? 'recovered' : 'opened'}';
  return PushNotificationOpenEvent(
    messageId: 'firebase-message-$recordId',
    data: _payload(
      type: type,
      eventKey: eventKey,
      recordKey: recordKey,
      recordId: recordId,
    ),
  );
}

class _FakeAuthService extends AuthService {
  _FakeAuthService(this._status);

  AuthStatus _status;

  @override
  AuthStatus get status => _status;

  @override
  AuthUser? get currentUser => null;

  void setStatus(AuthStatus value) {
    _status = value;
    notifyListeners();
  }

  @override
  Future<AuthUser?> signIn({
    required String email,
    required String password,
  }) async => null;

  @override
  Future<void> signOut() async {}
}

class _FakePushNotificationService implements PushNotificationService {
  _FakePushNotificationService({this.initialOpen});

  final PushNotificationOpenEvent? initialOpen;
  final StreamController<PushNotificationOpenEvent> opens =
      StreamController<PushNotificationOpenEvent>.broadcast(sync: true);

  @override
  bool get isAvailable => true;

  @override
  PushPermissionStatus get permissionStatus => PushPermissionStatus.authorized;

  @override
  String? get currentToken => null;

  @override
  String? get currentFirebaseInstallationId => null;

  @override
  Stream<String> get tokenChanges => const Stream<String>.empty();

  @override
  Stream<String> get firebaseInstallationIdChanges =>
      const Stream<String>.empty();

  @override
  Stream<PushNotificationOpenEvent> get notificationOpens => opens.stream;

  @override
  Future<void> initialize() async {
    final event = initialOpen;
    if (event != null) opens.add(event);
  }

  @override
  Future<void> dispose() => opens.close();
}

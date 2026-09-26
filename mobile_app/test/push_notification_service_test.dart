import 'dart:async';

import 'package:aqualogic/app/aqualogic_app.dart';
import 'package:aqualogic/features/auth/data/mock_auth_service.dart';
import 'package:aqualogic/features/auth/screens/login_screen.dart';
import 'package:aqualogic/features/push_notifications/data/notification_navigation_coordinator.dart';
import 'package:aqualogic/features/push_notifications/data/push_notification_service.dart';
import 'package:aqualogic/features/push_notifications/models/push_notification_message.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _FakePushNotificationPlatform platform;
  late FirebasePushNotificationService service;

  setUp(() {
    platform = _FakePushNotificationPlatform();
    service = FirebasePushNotificationService(platform: platform);
  });

  tearDown(() async {
    await service.dispose();
    await platform.dispose();
  });

  test(
    'initializes once, records permission, and obtains the FCM token',
    () async {
      const token = 'abcdef0123456789uvwxyz';
      final logs = <String>[];
      final previousDebugPrint = debugPrint;
      debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
      addTearDown(() => debugPrint = previousDebugPrint);

      final firstToken = service.tokenChanges.first;
      await Future.wait<void>(<Future<void>>[
        service.initialize(),
        service.initialize(),
        service.initialize(),
      ]);

      expect(platform.firebaseInitializationCount, 1);
      expect(platform.backgroundHandlerRegistrationCount, 1);
      expect(platform.localInitializationCount, 1);
      expect(platform.permissionRequestCount, 1);
      expect(platform.fidRegistrationCount, 1);
      expect(platform.tokenRequestCount, 1);
      expect(platform.fidRequestCount, 1);
      expect(service.isAvailable, isTrue);
      expect(service.permissionStatus, PushPermissionStatus.authorized);
      expect(service.currentToken, token);
      expect(
        service.currentFirebaseInstallationId,
        'firebase-installation-id-from-fake',
      );
      expect(await firstToken, token);
      expect(logs.join('\n'), isNot(contains(token)));
      expect(logs.join('\n'), isNot(contains('abcdef')));
      expect(logs.join('\n'), isNot(contains('firebase-installation-id')));
    },
  );

  test(
    'Firebase initialization failure leaves push unavailable safely',
    () async {
      platform.failFirebaseInitialization = true;

      await expectLater(service.initialize(), completes);

      expect(service.isAvailable, isFalse);
      expect(service.permissionStatus, PushPermissionStatus.unavailable);
      expect(service.currentToken, isNull);
      expect(platform.backgroundHandlerRegistrationCount, 0);
      expect(platform.permissionRequestCount, 0);
      expect(platform.fidRegistrationCount, 0);
      expect(platform.tokenRequestCount, 0);
    },
  );

  test('permission denial does not prevent token handling', () async {
    platform.permission = PushPermissionStatus.denied;

    await service.initialize();

    expect(service.isAvailable, isTrue);
    expect(service.permissionStatus, PushPermissionStatus.denied);
    expect(service.currentToken, isNotNull);
  });

  test('null or empty token is handled without exposing a token', () async {
    platform.token = null;
    await service.initialize();
    expect(service.currentToken, isNull);

    platform.refreshes.add('');
    await Future<void>.delayed(Duration.zero);
    expect(service.currentToken, isNull);
  });

  test('token refresh updates the current token and emits a change', () async {
    final tokens = <String>[];
    final subscription = service.tokenChanges.listen(tokens.add);
    await service.initialize();
    platform.refreshes.add('refreshed-fcm-token');
    await Future<void>.delayed(Duration.zero);

    expect(service.currentToken, 'refreshed-fcm-token');
    expect(tokens, <String>['abcdef0123456789uvwxyz', 'refreshed-fcm-token']);
    await subscription.cancel();
  });

  test(
    'Firebase Installation ID changes update state and emit separately',
    () async {
      final fids = <String>[];
      final subscription = service.firebaseInstallationIdChanges.listen(
        fids.add,
      );
      await service.initialize();
      platform.firebaseInstallationId = 'rotated-firebase-installation-id';
      platform.installationIdChanges.add('rotated-firebase-installation-id');
      await Future<void>.delayed(Duration.zero);

      expect(
        service.currentFirebaseInstallationId,
        'rotated-firebase-installation-id',
      );
      expect(fids, <String>[
        'firebase-installation-id-from-fake',
        'rotated-firebase-installation-id',
      ]);
      expect(platform.fidRegistrationCount, 2);
      await subscription.cancel();
    },
  );

  test('does not publish an FID when FCM FID registration fails', () async {
    platform.failFidRegistration = true;

    await service.initialize();

    expect(service.currentFirebaseInstallationId, isNull);
    expect(platform.fidRegistrationCount, 1);
  });

  test('foreground messages map title, body, and payload once', () async {
    await service.initialize();
    final message = PushNotificationMessage(
      messageId: 'message-1',
      title: 'Water quality alert',
      body: 'pH needs attention.',
      data: const <String, Object?>{
        'type': 'water_quality_alert',
        'alert_id': 'alert-7',
        'tank_id': 'tank-2',
      },
    );

    platform.foreground.add(message);
    platform.foreground.add(message);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(platform.presentedNotifications, hasLength(1));
    expect(platform.presentedNotifications.single.title, 'Water quality alert');
    expect(platform.presentedNotifications.single.body, 'pH needs attention.');
    expect(platform.presentedNotifications.single.data['alert_id'], 'alert-7');
  });

  test('foreground title and body can be read from data payload', () async {
    await service.initialize();
    platform.foreground.add(
      PushNotificationMessage(
        data: const <String, Object?>{'title': 'AquaLogic', 'body': 'Test'},
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(platform.presentedNotifications.single.title, 'AquaLogic');
    expect(platform.presentedNotifications.single.body, 'Test');
  });

  test(
    'buffers a foreground message until local notification setup finishes',
    () async {
      final localInitializationGate = Completer<void>();
      platform.localInitializationGate = localInitializationGate;
      final initialization = service.initialize();
      await Future<void>.delayed(Duration.zero);

      platform.foreground.add(
        PushNotificationMessage(title: 'Early alert', body: 'Still delivered'),
      );
      expect(platform.presentedNotifications, isEmpty);

      localInitializationGate.complete();
      await initialization;
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(platform.presentedNotifications, hasLength(1));
      expect(platform.presentedNotifications.single.title, 'Early alert');
    },
  );

  test(
    'unknown payload types remain safe and available on open events',
    () async {
      final opened = service.notificationOpens.first;
      await service.initialize();
      platform.opens.add(
        PushNotificationOpenEvent(
          data: const <String, Object?>{
            'type': 'future_event_type',
            'extra': 42,
          },
        ),
      );

      final event = await opened;
      expect(event.data['type'], 'future_event_type');
      expect(event.data['extra'], 42);
    },
  );

  test('captures initial Firebase and local notification opens', () async {
    final openedEvents = <PushNotificationOpenEvent>[];
    final subscription = service.notificationOpens.listen(openedEvents.add);
    platform.initialFirebaseOpen = PushNotificationOpenEvent(
      title: 'Backend alert',
      data: const <String, Object?>{'type': 'monitoring_incident'},
    );
    platform.initialLocalOpen = PushNotificationOpenEvent(
      title: 'Foreground alert',
      data: const <String, Object?>{'type': 'water_quality_alert'},
    );

    await service.initialize();

    expect(openedEvents, hasLength(2));
    expect(openedEvents[0].data['type'], 'monitoring_incident');
    expect(openedEvents[1].data['type'], 'water_quality_alert');
    await subscription.cancel();
  });

  test(
    'initial, background Firebase, and local taps share one coordinator',
    () async {
      final auth = MockAuthService();
      await auth.signIn(email: 'staff@aqualogic.local', password: 'staff123');
      platform.initialFirebaseOpen = _validOpenEvent(
        'water_quality_alert',
        '70',
      );
      platform.initialLocalOpen = _validOpenEvent('monitoring_recovered', '71');
      final navigations = <String>[];
      final coordinator = NotificationNavigationCoordinator(
        authService: auth,
        pushNotificationService: service,
        navigate: (intent) {
          if (intent != null) navigations.add(intent.eventKey);
          return true;
        },
      )..start();
      coordinator.onAuthenticatedShellReady();
      await service.initialize();

      platform.opens.add(_validOpenEvent('monitoring_incident', '72'));
      platform.localOpens.add(_validOpenEvent('monitoring_recovered', '73'));
      await Future<void>.delayed(Duration.zero);

      expect(navigations, [
        'water_quality_alert:70:created',
        'monitoring_incident:71:recovered',
        'monitoring_incident:72:opened',
        'monitoring_incident:73:recovered',
      ]);
      await coordinator.dispose();
      auth.dispose();
    },
  );

  test(
    'local notification setup failure does not block FCM registration',
    () async {
      platform.failLocalInitialization = true;

      await service.initialize();

      expect(service.isAvailable, isTrue);
      expect(service.currentToken, isNotNull);
      platform.foreground.add(
        PushNotificationMessage(title: 'Alert', body: 'Payload'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(platform.presentedNotifications, isEmpty);
    },
  );

  testWidgets(
    'injected notification service keeps Login usable when permission is denied',
    (tester) async {
      final fake = _FakePushNotificationService();

      await tester.pumpWidget(
        AquaLogicApp(
          authService: MockAuthService(),
          pushNotificationService: fake,
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      expect(fake.initializeCount, 1);
      expect(fake.permissionStatus, PushPermissionStatus.denied);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text('injected-token-must-not-appear'), findsNothing);

      fake.opens.add(
        PushNotificationOpenEvent(
          data: const <String, Object?>{'type': 'unknown_future_type'},
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await fake.dispose();
    },
  );

  testWidgets(
    'cold-start push open waits for sign-in before using authenticated navigation',
    (tester) async {
      final auth = MockAuthService();
      final fake = _FakePushNotificationService(
        initialOpen: PushNotificationOpenEvent(
          messageId: 'cold-start-unknown',
          data: const <String, Object?>{'type': 'future_event_type'},
        ),
      );
      await tester.pumpWidget(
        AquaLogicApp(authService: auth, pushNotificationService: fake),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text('This notification could not be opened.'), findsNothing);

      final signIn = auth.signIn(
        email: 'staff@aqualogic.local',
        password: 'staff123',
      );
      await tester.pump(const Duration(milliseconds: 220));
      await signIn;
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();

      expect(find.byType(LoginScreen), findsNothing);
      expect(
        find.text('This notification could not be opened.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      auth.dispose();
      await fake.dispose();
    },
  );

  testWidgets('Firebase startup failure does not block the auth flow', (
    tester,
  ) async {
    platform.failFirebaseInitialization = true;

    await tester.pumpWidget(
      AquaLogicApp(
        authService: MockAuthService(),
        pushNotificationService: service,
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    expect(service.isAvailable, isFalse);
    expect(find.byType(LoginScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

PushNotificationOpenEvent _validOpenEvent(String type, String recordId) {
  final alert = type == 'water_quality_alert';
  final recovered = type == 'monitoring_recovered';
  final eventKey = alert
      ? 'water_quality_alert:$recordId:created'
      : 'monitoring_incident:$recordId:${recovered ? 'recovered' : 'opened'}';
  return PushNotificationOpenEvent(
    messageId: 'fake-message-$type-$recordId',
    data: <String, Object?>{
      'schema_version': '1',
      'type': type,
      'event_key': eventKey,
      'tank_id': '8',
      alert ? 'alert_id' : 'incident_id': recordId,
    },
  );
}

class _FakePushNotificationPlatform implements PushNotificationPlatform {
  final StreamController<String> refreshes = StreamController<String>.broadcast(
    sync: true,
  );
  final StreamController<String> installationIdChanges =
      StreamController<String>.broadcast(sync: true);
  final StreamController<PushNotificationMessage> foreground =
      StreamController<PushNotificationMessage>.broadcast(sync: true);
  final StreamController<PushNotificationOpenEvent> opens =
      StreamController<PushNotificationOpenEvent>.broadcast(sync: true);
  final StreamController<PushNotificationOpenEvent> localOpens =
      StreamController<PushNotificationOpenEvent>.broadcast(sync: true);
  final List<PushNotificationMessage> presentedNotifications =
      <PushNotificationMessage>[];

  var firebaseInitializationCount = 0;
  var backgroundHandlerRegistrationCount = 0;
  var localInitializationCount = 0;
  var permissionRequestCount = 0;
  var fidRegistrationCount = 0;
  var tokenRequestCount = 0;
  var fidRequestCount = 0;
  var failFirebaseInitialization = false;
  var failFidRegistration = false;
  var failLocalInitialization = false;
  Completer<void>? localInitializationGate;
  var permission = PushPermissionStatus.authorized;
  String? token = 'abcdef0123456789uvwxyz';
  String firebaseInstallationId = 'firebase-installation-id-from-fake';
  PushNotificationOpenEvent? initialFirebaseOpen;
  PushNotificationOpenEvent? initialLocalOpen;

  @override
  Future<void> initializeFirebase() async {
    firebaseInitializationCount++;
    if (failFirebaseInitialization) throw StateError('Firebase unavailable');
  }

  @override
  void registerBackgroundHandler() {
    backgroundHandlerRegistrationCount++;
  }

  @override
  Future<void> initializeLocalNotifications() async {
    localInitializationCount++;
    final gate = localInitializationGate;
    if (gate != null) await gate.future;
    if (failLocalInitialization) {
      throw StateError('Local notifications unavailable');
    }
  }

  @override
  Future<PushPermissionStatus> requestPermission() async {
    permissionRequestCount++;
    return permission;
  }

  @override
  Future<void> registerFidForMessaging() async {
    fidRegistrationCount++;
    if (failFidRegistration) throw StateError('FCM registration unavailable');
  }

  @override
  Future<String?> getToken() async {
    tokenRequestCount++;
    return token;
  }

  @override
  Future<String> getFirebaseInstallationId() async {
    fidRequestCount++;
    return firebaseInstallationId;
  }

  @override
  Stream<String> get tokenRefreshes => refreshes.stream;

  @override
  Stream<String> get firebaseInstallationIdRefreshes =>
      installationIdChanges.stream;

  @override
  Stream<PushNotificationMessage> get foregroundMessages => foreground.stream;

  @override
  Stream<PushNotificationOpenEvent> get notificationOpens => opens.stream;

  @override
  Stream<PushNotificationOpenEvent> get localNotificationOpens =>
      localOpens.stream;

  @override
  Future<PushNotificationOpenEvent?> getInitialNotificationOpen() async =>
      initialFirebaseOpen;

  @override
  Future<PushNotificationOpenEvent?> getInitialLocalNotificationOpen() async =>
      initialLocalOpen;

  @override
  Future<void> showForegroundNotification(
    PushNotificationMessage message,
  ) async {
    presentedNotifications.add(message);
  }

  Future<void> dispose() async {
    await refreshes.close();
    await installationIdChanges.close();
    await foreground.close();
    await opens.close();
    await localOpens.close();
  }
}

class _FakePushNotificationService implements PushNotificationService {
  _FakePushNotificationService({this.initialOpen});

  final PushNotificationOpenEvent? initialOpen;
  final StreamController<String> tokens = StreamController<String>.broadcast(
    sync: true,
  );
  final StreamController<String> fids = StreamController<String>.broadcast(
    sync: true,
  );
  final StreamController<PushNotificationOpenEvent> opens =
      StreamController<PushNotificationOpenEvent>.broadcast(sync: true);

  var initializeCount = 0;

  @override
  bool get isAvailable => true;

  @override
  PushPermissionStatus get permissionStatus => PushPermissionStatus.denied;

  @override
  String? get currentToken => 'injected-token-must-not-appear';

  @override
  String? get currentFirebaseInstallationId => 'injected-fid-must-not-appear';

  @override
  Stream<String> get tokenChanges => tokens.stream;

  @override
  Stream<String> get firebaseInstallationIdChanges => fids.stream;

  @override
  Stream<PushNotificationOpenEvent> get notificationOpens => opens.stream;

  @override
  Future<void> initialize() async {
    initializeCount++;
    final event = initialOpen;
    if (event != null) opens.add(event);
  }

  @override
  Future<void> dispose() async {
    await tokens.close();
    await fids.close();
    await opens.close();
  }
}

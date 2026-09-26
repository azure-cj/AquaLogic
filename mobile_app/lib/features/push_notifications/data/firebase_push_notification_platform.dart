import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:aqualogic/features/push_notifications/data/push_notification_service.dart';
import 'package:aqualogic/features/push_notifications/models/push_notification_message.dart';

const aqualogicAlertsChannelId = 'aqualogic_alerts';
const aqualogicAlertsChannelName = 'AquaLogic Alerts';
const aqualogicAlertsChannelDescription =
    'Water-quality and aquarium monitoring alerts.';
const aqualogicNotificationIcon = 'ic_stat_aqualogic';

@pragma('vm:entry-point')
Future<void> aquaLogicFirebaseMessagingBackgroundHandler(
  RemoteMessage message,
) async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    if (Firebase.apps.isEmpty) await Firebase.initializeApp();
  } catch (error) {
    if (kDebugMode) {
      debugPrint(
        'Background Firebase initialization unavailable (${error.runtimeType}).',
      );
    }
  }
}

class FirebasePushNotificationPlatform implements PushNotificationPlatform {
  FirebasePushNotificationPlatform({
    FlutterLocalNotificationsPlugin? localNotifications,
  }) : _localNotifications =
           localNotifications ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _localNotifications;
  final StreamController<PushNotificationOpenEvent> _localOpensController =
      StreamController<PushNotificationOpenEvent>.broadcast();
  var _localNotificationsInitialized = false;
  var _nextLocalNotificationId = 0;

  @override
  Future<void> initializeFirebase() async {
    if (Firebase.apps.isEmpty) await Firebase.initializeApp();
  }

  @override
  void registerBackgroundHandler() {
    FirebaseMessaging.onBackgroundMessage(
      aquaLogicFirebaseMessagingBackgroundHandler,
    );
  }

  @override
  Future<void> initializeLocalNotifications() async {
    await _localNotifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings(aqualogicNotificationIcon),
      ),
      onDidReceiveNotificationResponse: _handleLocalNotificationResponse,
    );

    final androidNotifications = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidNotifications?.createNotificationChannel(
      const AndroidNotificationChannel(
        aqualogicAlertsChannelId,
        aqualogicAlertsChannelName,
        description: aqualogicAlertsChannelDescription,
        importance: Importance.high,
      ),
    );
    _localNotificationsInitialized = true;
  }

  @override
  Future<PushPermissionStatus> requestPermission() async {
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    return switch (settings.authorizationStatus) {
      AuthorizationStatus.authorized => PushPermissionStatus.authorized,
      AuthorizationStatus.provisional => PushPermissionStatus.provisional,
      AuthorizationStatus.denied => PushPermissionStatus.denied,
      AuthorizationStatus.deniedPermanently => PushPermissionStatus.denied,
      AuthorizationStatus.notDetermined => PushPermissionStatus.unknown,
    };
  }

  @override
  Future<String?> getToken() => FirebaseMessaging.instance.getToken();

  @override
  Stream<String> get tokenRefreshes =>
      FirebaseMessaging.instance.onTokenRefresh;

  @override
  Stream<PushNotificationMessage> get foregroundMessages =>
      FirebaseMessaging.onMessage.map(_fromRemoteMessage);

  @override
  Stream<PushNotificationOpenEvent> get notificationOpens =>
      FirebaseMessaging.onMessageOpenedApp.map(_openEventFromRemoteMessage);

  @override
  Stream<PushNotificationOpenEvent> get localNotificationOpens =>
      _localOpensController.stream;

  @override
  Future<PushNotificationOpenEvent?> getInitialNotificationOpen() async {
    final message = await FirebaseMessaging.instance.getInitialMessage();
    return message == null ? null : _openEventFromRemoteMessage(message);
  }

  @override
  Future<PushNotificationOpenEvent?> getInitialLocalNotificationOpen() async {
    final details = await _localNotifications.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp != true) return null;
    return _openEventFromPayload(details?.notificationResponse?.payload);
  }

  @override
  Future<void> showForegroundNotification(
    PushNotificationMessage message,
  ) async {
    if (!_localNotificationsInitialized) return;
    final payload = jsonEncode(<String, Object?>{
      'title': message.title,
      'body': message.body,
      'data': message.data,
    });
    await _localNotifications.show(
      id: ++_nextLocalNotificationId,
      title: message.title,
      body: message.body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          aqualogicAlertsChannelId,
          aqualogicAlertsChannelName,
          channelDescription: aqualogicAlertsChannelDescription,
          icon: aqualogicNotificationIcon,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: payload,
    );
  }

  void _handleLocalNotificationResponse(NotificationResponse response) {
    final event = _openEventFromPayload(response.payload);
    if (event != null) _localOpensController.add(event);
  }

  PushNotificationOpenEvent _openEventFromRemoteMessage(RemoteMessage message) {
    final notification = message.notification;
    return PushNotificationOpenEvent(
      title: notification?.title,
      body: notification?.body,
      data: Map<String, Object?>.from(message.data),
    );
  }

  PushNotificationMessage _fromRemoteMessage(RemoteMessage message) {
    final notification = message.notification;
    return PushNotificationMessage(
      messageId: message.messageId,
      title: notification?.title,
      body: notification?.body,
      data: Map<String, Object?>.from(message.data),
    );
  }

  PushNotificationOpenEvent? _openEventFromPayload(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic>) return null;
      final data = decoded['data'];
      return PushNotificationOpenEvent(
        title: decoded['title'] is String ? decoded['title'] as String : null,
        body: decoded['body'] is String ? decoded['body'] as String : null,
        data: data is Map<String, dynamic>
            ? Map<String, Object?>.from(data)
            : const <String, Object?>{},
      );
    } on FormatException {
      return null;
    }
  }
}

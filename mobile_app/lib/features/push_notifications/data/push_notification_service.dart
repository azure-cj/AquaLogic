import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:aqualogic/features/push_notifications/models/push_notification_message.dart';

abstract interface class PushNotificationService {
  bool get isAvailable;
  PushPermissionStatus get permissionStatus;
  String? get currentToken;
  Stream<String> get tokenChanges;
  Stream<PushNotificationOpenEvent> get notificationOpens;

  Future<void> initialize();
  Future<void> dispose();
}

abstract interface class PushNotificationPlatform {
  Future<void> initializeFirebase();
  void registerBackgroundHandler();
  Future<void> initializeLocalNotifications();
  Future<PushPermissionStatus> requestPermission();
  Future<String?> getToken();

  Stream<String> get tokenRefreshes;
  Stream<PushNotificationMessage> get foregroundMessages;
  Stream<PushNotificationOpenEvent> get notificationOpens;
  Stream<PushNotificationOpenEvent> get localNotificationOpens;

  Future<PushNotificationOpenEvent?> getInitialNotificationOpen();
  Future<PushNotificationOpenEvent?> getInitialLocalNotificationOpen();
  Future<void> showForegroundNotification(PushNotificationMessage message);
}

/// Coordinates Firebase Messaging behind one app-level boundary.
///
/// Initialization is idempotent and non-blocking for the widget tree. A
/// Firebase startup failure leaves push unavailable without affecting auth or
/// the rest of AquaLogic.
class FirebasePushNotificationService implements PushNotificationService {
  FirebasePushNotificationService({required this.platform});

  final PushNotificationPlatform platform;
  final StreamController<String> _tokenChangesController =
      StreamController<String>.broadcast();
  final StreamController<PushNotificationOpenEvent> _opensController =
      StreamController<PushNotificationOpenEvent>.broadcast();
  final List<StreamSubscription<dynamic>> _subscriptions =
      <StreamSubscription<dynamic>>[];
  final Set<String> _presentedMessageIds = <String>{};
  final List<PushNotificationMessage> _pendingForegroundMessages =
      <PushNotificationMessage>[];

  Future<void>? _initialization;
  String? _currentToken;
  var _isAvailable = false;
  var _localNotificationsAvailable = false;
  var _permissionStatus = PushPermissionStatus.unknown;

  @override
  bool get isAvailable => _isAvailable;

  @override
  PushPermissionStatus get permissionStatus => _permissionStatus;

  @override
  String? get currentToken => _currentToken;

  @override
  Stream<String> get tokenChanges => _tokenChangesController.stream;

  @override
  Stream<PushNotificationOpenEvent> get notificationOpens =>
      _opensController.stream;

  @override
  Future<void> initialize() => _initialization ??= _initializeOnce();

  @override
  Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _tokenChangesController.close();
    await _opensController.close();
  }

  Future<void> _initializeOnce() async {
    try {
      await platform.initializeFirebase();
      platform.registerBackgroundHandler();
      _isAvailable = true;
    } catch (error) {
      _permissionStatus = PushPermissionStatus.unavailable;
      _debugFailure('Firebase initialization', error);
      return;
    }

    _listenForMessages();

    try {
      await platform.initializeLocalNotifications();
      _localNotificationsAvailable = true;
      final pendingMessages = List<PushNotificationMessage>.of(
        _pendingForegroundMessages,
      );
      _pendingForegroundMessages.clear();
      for (final message in pendingMessages) {
        unawaited(_presentForegroundMessage(message));
      }
    } catch (error) {
      _pendingForegroundMessages.clear();
      _debugFailure('Local notification setup', error);
    }

    await _captureInitialOpen(
      platform.getInitialNotificationOpen,
      'Initial Firebase notification',
    );
    await _captureInitialOpen(
      platform.getInitialLocalNotificationOpen,
      'Initial local notification',
    );

    try {
      _permissionStatus = await platform.requestPermission();
      if (kDebugMode) {
        debugPrint('Notification permission: ${_permissionStatus.name}.');
      }
    } catch (error) {
      _permissionStatus = PushPermissionStatus.unavailable;
      _debugFailure('Notification permission request', error);
    }

    try {
      _setToken(await platform.getToken());
    } catch (error) {
      _debugFailure('FCM token request', error);
    }
  }

  void _listenForMessages() {
    _subscriptions.add(
      platform.tokenRefreshes.listen(
        _setToken,
        onError: (Object error) => _debugFailure('FCM token refresh', error),
      ),
    );
    _subscriptions.add(
      platform.foregroundMessages.listen(
        _receiveForegroundMessage,
        onError: (Object error) =>
            _debugFailure('Foreground FCM message', error),
      ),
    );
    _subscriptions.add(
      platform.notificationOpens.listen(
        _opensController.add,
        onError: (Object error) =>
            _debugFailure('Notification open event', error),
      ),
    );
    _subscriptions.add(
      platform.localNotificationOpens.listen(
        _opensController.add,
        onError: (Object error) =>
            _debugFailure('Local notification open event', error),
      ),
    );
  }

  Future<void> _captureInitialOpen(
    Future<PushNotificationOpenEvent?> Function() readInitialOpen,
    String operation,
  ) async {
    try {
      final event = await readInitialOpen();
      if (event != null) _opensController.add(event);
    } catch (error) {
      _debugFailure(operation, error);
    }
  }

  Future<void> _presentForegroundMessage(
    PushNotificationMessage message,
  ) async {
    final messageId = message.messageId;
    if (messageId != null && !_presentedMessageIds.add(messageId)) return;
    if (_presentedMessageIds.length > 100) _presentedMessageIds.clear();
    if (!_localNotificationsAvailable) return;

    final title = _nonEmpty(message.title) ?? _nonEmpty(message.data['title']);
    final body = _nonEmpty(message.body) ?? _nonEmpty(message.data['body']);
    if (title == null && body == null) return;

    try {
      await platform.showForegroundNotification(
        PushNotificationMessage(
          messageId: messageId,
          title: title,
          body: body,
          data: message.data,
        ),
      );
    } catch (error) {
      _debugFailure('Foreground notification display', error);
    }
  }

  void _receiveForegroundMessage(PushNotificationMessage message) {
    if (!_localNotificationsAvailable) {
      _pendingForegroundMessages.add(message);
      return;
    }
    unawaited(_presentForegroundMessage(message));
  }

  String? _nonEmpty(Object? value) {
    if (value is! String || value.trim().isEmpty) return null;
    return value;
  }

  void _setToken(String? token) {
    if (token == null || token.isEmpty || token == _currentToken) return;
    final isRefresh = _currentToken != null;
    _currentToken = token;
    _tokenChangesController.add(token);
    if (kDebugMode) {
      final label = isRefresh ? 'refreshed' : 'obtained';
      debugPrint('FCM token $label (${token.length} chars; ${_mask(token)}).');
    }
  }

  String _mask(String token) {
    if (token.length <= 10) return '***';
    return '${token.substring(0, 6)}…${token.substring(token.length - 4)}';
  }

  void _debugFailure(String operation, Object error) {
    if (kDebugMode) {
      debugPrint('$operation unavailable (${error.runtimeType}).');
    }
  }
}

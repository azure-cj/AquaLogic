import 'dart:async';
import 'dart:collection';

import 'package:aqualogic/features/auth/data/mock_auth_service.dart';
import 'package:aqualogic/features/push_notifications/data/push_notification_service.dart';
import 'package:aqualogic/features/push_notifications/models/push_notification_intent.dart';
import 'package:aqualogic/features/push_notifications/models/push_notification_message.dart';

typedef PushNotificationIntentHandler =
    FutureOr<bool> Function(PushNotificationIntent? intent);

/// Holds one in-memory notification intent until authenticated navigation is
/// ready, then routes it once through the app's existing operational screens.
class NotificationNavigationCoordinator {
  NotificationNavigationCoordinator({
    required this.authService,
    required this.pushNotificationService,
    required this.navigate,
  });

  static const _maxRecentlySeen = 100;

  final AuthService authService;
  final PushNotificationService pushNotificationService;
  final PushNotificationIntentHandler navigate;
  final Queue<String> _recentOrder = Queue<String>();
  final Set<String> _recentKeys = <String>{};

  StreamSubscription<PushNotificationOpenEvent>? _openSubscription;
  PushNotificationIntent? _pendingIntent;
  var _hasPendingIntent = false;
  var _authenticatedShellReady = false;
  var _processing = false;
  var _started = false;
  var _disposed = false;

  void start() {
    if (_started || _disposed) return;
    _started = true;
    authService.addListener(_onAuthChanged);
    _openSubscription = pushNotificationService.notificationOpens.listen(
      _onNotificationOpen,
      onError: (Object _) {},
    );
    _onAuthChanged();
  }

  /// Called after AuthGate has mounted the authenticated AquaLogic shell.
  void onAuthenticatedShellReady() {
    if (_disposed || authService.status != AuthStatus.authenticated) return;
    _authenticatedShellReady = true;
    unawaited(_drainPendingIntent());
  }

  Future<void> dispose() async {
    _disposed = true;
    authService.removeListener(_onAuthChanged);
    await _openSubscription?.cancel();
    _openSubscription = null;
  }

  void _onAuthChanged() {
    if (authService.status != AuthStatus.authenticated) {
      _authenticatedShellReady = false;
      return;
    }
    unawaited(_drainPendingIntent());
  }

  void _onNotificationOpen(PushNotificationOpenEvent event) {
    if (_disposed || !_remember(_deduplicationKey(event))) return;
    // There is intentionally one pending slot. A newer tap supersedes an
    // older unprocessed one while startup/authentication is still pending.
    _pendingIntent = PushNotificationIntent.parse(event);
    _hasPendingIntent = true;
    unawaited(_drainPendingIntent());
  }

  bool _remember(String key) {
    if (!_recentKeys.add(key)) return false;
    _recentOrder.addLast(key);
    if (_recentOrder.length > _maxRecentlySeen) {
      _recentKeys.remove(_recentOrder.removeFirst());
    }
    return true;
  }

  String _deduplicationKey(PushNotificationOpenEvent event) {
    final eventKey = event.data['event_key'];
    if (eventKey is String && eventKey.isNotEmpty) return 'event:$eventKey';

    final messageId = event.messageId;
    if (messageId != null && messageId.isNotEmpty) return 'message:$messageId';

    final entries = event.data.entries.map((entry) {
      final value = entry.value;
      return '${entry.key}=${value is String ? value : value.runtimeType}';
    }).toList()..sort();
    return 'payload:${entries.join('|')}';
  }

  Future<void> _drainPendingIntent() async {
    if (_disposed ||
        _processing ||
        !_hasPendingIntent ||
        !_authenticatedShellReady ||
        authService.status != AuthStatus.authenticated) {
      return;
    }

    final intent = _pendingIntent;
    _pendingIntent = null;
    _hasPendingIntent = false;
    _processing = true;
    var handled = false;
    try {
      handled = await navigate(intent);
    } catch (_) {
      // Navigation failures stay inside this optional push boundary. Fall back
      // to the safe Alerts destination without using notification record data.
      try {
        handled = await navigate(null);
      } catch (_) {
        handled = false;
      }
    } finally {
      _processing = false;
    }

    if (!handled && !_disposed) {
      _pendingIntent = intent;
      _hasPendingIntent = true;
      _authenticatedShellReady = false;
    }
    if (_hasPendingIntent && _authenticatedShellReady) {
      unawaited(_drainPendingIntent());
    }
  }
}

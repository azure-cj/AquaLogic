import 'package:flutter/foundation.dart';

@immutable
class PushNotificationMessage {
  PushNotificationMessage({
    this.messageId,
    this.title,
    this.body,
    Map<String, Object?> data = const <String, Object?>{},
  }) : data = Map<String, Object?>.unmodifiable(data);

  final String? messageId;
  final String? title;
  final String? body;
  final Map<String, Object?> data;
}

@immutable
class PushNotificationOpenEvent {
  PushNotificationOpenEvent({
    this.messageId,
    this.title,
    this.body,
    Map<String, Object?> data = const <String, Object?>{},
  }) : data = Map<String, Object?>.unmodifiable(data);

  final String? messageId;
  final String? title;
  final String? body;
  final Map<String, Object?> data;
}

enum PushPermissionStatus {
  unknown,
  denied,
  authorized,
  provisional,
  unavailable,
}

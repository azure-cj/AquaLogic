import 'package:aqualogic/app/aqualogic_app.dart';
import 'package:aqualogic/features/push_notifications/data/firebase_push_notification_platform.dart';
import 'package:aqualogic/features/push_notifications/data/push_notification_service.dart';
import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final pushNotificationService = FirebasePushNotificationService(
    platform: FirebasePushNotificationPlatform(),
  );
  runApp(AquaLogicApp(pushNotificationService: pushNotificationService));
}

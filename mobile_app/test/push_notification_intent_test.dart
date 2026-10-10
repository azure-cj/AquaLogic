import 'package:aqualogic/features/push_notifications/models/push_notification_intent.dart';
import 'package:aqualogic/features/push_notifications/models/push_notification_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, Object?> payload() => <String, Object?>{
    'schema_version': '1',
    'type': 'water_quality_alert_escalated',
    'event_key': 'water_quality_alert:42:escalated',
    'tank_id': '7',
    'alert_id': '42',
  };

  test('escalation opens the existing water quality alert target', () {
    final intent = PushNotificationIntent.parse(
      PushNotificationOpenEvent(data: payload()),
    );
    expect(intent, isNotNull);
    expect(intent!.kind, PushNotificationIntentKind.waterQualityAlert);
    expect(intent.recordId, '42');
    expect(intent.tankId, '7');
    expect(intent.eventKey, 'water_quality_alert:42:escalated');
  });

  for (final change in <Map<String, Object?>>[
    {'event_key': 'water_quality_alert:42:created'},
    {'event_key': 'water_quality_alert:41:escalated'},
    {'event_key': 'water_quality_alert_escalated:42:escalated'},
    {'alert_id': '042'},
    {'alert_id': '0'},
    {'alert_id': 42},
    {'tank_id': '-1'},
    {'schema_version': '2'},
    {'type': 'water_quality_alert'},
  ]) {
    test('strict escalation payload rejects $change', () {
      expect(
        PushNotificationIntent.parse(
          PushNotificationOpenEvent(data: payload()..addAll(change)),
        ),
        isNull,
      );
    });
  }
  test('escalation requires alert identity', () {
    expect(
      PushNotificationIntent.parse(
        PushNotificationOpenEvent(data: payload()..remove('alert_id')),
      ),
      isNull,
    );
  });
}

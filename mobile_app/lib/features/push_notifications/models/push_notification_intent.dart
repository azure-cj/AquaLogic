import 'package:aqualogic/features/push_notifications/models/push_notification_message.dart';

enum PushNotificationIntentKind {
  waterQualityAlert,
  monitoringIncident,
  monitoringRecovered,
}

class PushNotificationIntent {
  const PushNotificationIntent({
    required this.kind,
    required this.eventKey,
    required this.recordId,
    required this.tankId,
  });

  final PushNotificationIntentKind kind;
  final String eventKey;
  final String recordId;
  final String tankId;

  static PushNotificationIntent? parse(PushNotificationOpenEvent event) {
    final data = event.data;
    if (data.values.any((value) => value is! String)) return null;

    final schemaVersion = data['schema_version'];
    final type = data['type'];
    final eventKey = data['event_key'];
    final tankId = _positiveId(data['tank_id']);
    if (schemaVersion != '1' ||
        eventKey is! String ||
        eventKey.isEmpty ||
        tankId == null) {
      return null;
    }

    switch (type) {
      case 'water_quality_alert':
        final alertId = _positiveId(data['alert_id']);
        if (alertId == null ||
            eventKey != 'water_quality_alert:$alertId:created') {
          return null;
        }
        return PushNotificationIntent(
          kind: PushNotificationIntentKind.waterQualityAlert,
          eventKey: eventKey,
          recordId: alertId,
          tankId: tankId,
        );
      case 'monitoring_incident':
        final incidentId = _positiveId(data['incident_id']);
        if (incidentId == null ||
            eventKey != 'monitoring_incident:$incidentId:opened') {
          return null;
        }
        return PushNotificationIntent(
          kind: PushNotificationIntentKind.monitoringIncident,
          eventKey: eventKey,
          recordId: incidentId,
          tankId: tankId,
        );
      case 'monitoring_recovered':
        final incidentId = _positiveId(data['incident_id']);
        if (incidentId == null ||
            eventKey != 'monitoring_incident:$incidentId:recovered') {
          return null;
        }
        return PushNotificationIntent(
          kind: PushNotificationIntentKind.monitoringRecovered,
          eventKey: eventKey,
          recordId: incidentId,
          tankId: tankId,
        );
      default:
        return null;
    }
  }

  static String? _positiveId(Object? value) {
    if (value is! String || value.isEmpty) return null;
    final parsed = int.tryParse(value);
    if (parsed == null || parsed <= 0 || parsed.toString() != value) {
      return null;
    }
    return value;
  }
}

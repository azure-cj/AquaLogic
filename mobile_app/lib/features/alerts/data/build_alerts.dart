import 'package:aqualogic/features/alerts/data/mock_alert_repository.dart';
import 'package:aqualogic/features/alerts/models/alert_info.dart';
import 'package:aqualogic/features/sensors/models/sensor_snapshot.dart';

/// Compatibility helper for the older Home alert shortcut. New screens use
/// AlertRepository and keep monitoring incidents in their own collection.
List<AlertInfo> buildAlerts(SensorSnapshot snapshot) {
  return const MockAlertRepository()
      .load(snapshot: snapshot)
      .activeWaterQualityAlerts;
}

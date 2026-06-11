import 'package:aqualogic/features/alerts/models/alert_info.dart';
import 'package:aqualogic/features/sensors/models/sensor_snapshot.dart';
import 'package:aqualogic/shared/models/reading_state.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

List<AlertInfo> buildAlerts(SensorSnapshot snapshot) {
  final alerts = <AlertInfo>[];
  if (!snapshot.isOnline) {
    alerts.add(
      const AlertInfo(
        icon: LucideIcons.wifiOff,
        title: 'ESP32 offline',
        message: 'Sensor node is not reachable on the local network.',
        recommendation: 'Check Wi-Fi and device power',
        time: 'now',
        state: ReadingState.critical,
      ),
    );
  }
  if (snapshot.phStatus != 'NORMAL') {
    alerts.add(
      AlertInfo(
        icon: LucideIcons.triangleAlert,
        title: 'pH ${snapshot.phStatus.toLowerCase()}',
        message: 'pH is ${snapshot.ph.toStringAsFixed(1)} outside 6.5-8.0.',
        recommendation: 'Adjust pH buffer',
        time: '2 min ago',
        state: ReadingState.warning,
      ),
    );
  }
  if (snapshot.turbidityStatus == 'DIRTY') {
    alerts.add(
      const AlertInfo(
        icon: LucideIcons.circleAlert,
        title: 'Dirty water',
        message: 'Turbidity dropped below the safe clarity range.',
        recommendation: 'Trigger partial water replacement',
        time: '8 min ago',
        state: ReadingState.critical,
      ),
    );
  }
  if (snapshot.tdsStatus == 'HIGH') {
    alerts.add(
      const AlertInfo(
        icon: LucideIcons.triangleAlert,
        title: 'TDS high',
        message: 'Mineral concentration exceeded the normal range.',
        recommendation: 'Prepare water change',
        time: '12 min ago',
        state: ReadingState.critical,
      ),
    );
  }
  if (snapshot.tempStatus != 'NORMAL') {
    alerts.add(
      AlertInfo(
        icon: LucideIcons.thermometer,
        title: 'Temperature ${snapshot.tempStatus.toLowerCase()}',
        message:
            'Temperature is ${snapshot.temperatureC.toStringAsFixed(1)}°C.',
        recommendation: 'Check heater or cooling fan',
        time: '18 min ago',
        state: ReadingState.warning,
      ),
    );
  }
  if (alerts.isEmpty) {
    alerts.add(
      const AlertInfo(
        icon: LucideIcons.circleCheck,
        title: 'System normal',
        message: 'All tracked sensor values are inside the v1 target range.',
        recommendation: 'No action required',
        time: 'now',
        state: ReadingState.normal,
      ),
    );
  }
  alerts.addAll(const [
    AlertInfo(
      icon: LucideIcons.circleCheck,
      title: 'Feeding completed',
      message: 'Auto-feed cycle finished successfully.',
      recommendation: 'No action required',
      time: '2h ago',
      state: ReadingState.normal,
    ),
    AlertInfo(
      icon: LucideIcons.circleCheck,
      title: 'UV cycle complete',
      message: 'Sterilization ran for 45 minutes.',
      recommendation: 'No action required',
      time: '3h ago',
      state: ReadingState.normal,
    ),
  ]);
  return alerts;
}

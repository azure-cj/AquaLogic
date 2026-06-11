import 'dart:math' as math;
import 'package:aqualogic/features/sensors/models/sensor_snapshot.dart';

class MockSensorFeed {
  static SensorSnapshot snapshot(int tick) {
    final wave = math.sin(tick / 3);
    final slowWave = math.sin(tick / 7);
    final isOnline = tick % 19 != 14;
    final temperature = 27.1 + wave * 2.1;
    final ph = tick % 16 == 10 ? 8.3 : 7.2 + slowWave * 0.45;
    final turbidity = tick % 13 == 8 ? 1320 : 2450 + (wave * 430).round();
    final tds = tick % 17 == 11 ? 2370 : 980 + (slowWave * 290).round();
    final tempStatus = temperature < 24
        ? 'LOW'
        : temperature > 30
        ? 'HIGH'
        : 'NORMAL';
    final phStatus = ph < 6.5
        ? 'LOW'
        : ph > 8.0
        ? 'HIGH'
        : 'NORMAL';
    final turbidityStatus = turbidity > 2500
        ? 'CLEAR'
        : turbidity > 1500
        ? 'MODERATE'
        : 'DIRTY';
    final tdsStatus = tds < 800
        ? 'LOW'
        : tds <= 2200
        ? 'NORMAL'
        : 'HIGH';
    final hasCritical = turbidityStatus == 'DIRTY' || tdsStatus == 'HIGH';
    final hasMonitor = [
      tempStatus,
      phStatus,
      turbidityStatus,
      tdsStatus,
    ].any((status) => status != 'NORMAL' && status != 'CLEAR');

    return SensorSnapshot(
      temperatureC: temperature,
      tempStatus: tempStatus,
      ph: ph,
      phStatus: phStatus,
      turbidityRaw: turbidity,
      turbidityStatus: turbidityStatus,
      tdsRaw: tds,
      tdsStatus: tdsStatus,
      overallStatus: hasCritical
          ? 'CRITICAL'
          : hasMonitor
          ? 'MONITOR'
          : 'GOOD',
      isOnline: isOnline,
      updatedAt: DateTime.now(),
    );
  }
}

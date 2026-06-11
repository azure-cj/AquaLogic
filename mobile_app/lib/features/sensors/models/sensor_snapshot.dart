import 'package:aqualogic/shared/models/reading_state.dart';

class SensorSnapshot {
  const SensorSnapshot({
    required this.temperatureC,
    required this.tempStatus,
    required this.ph,
    required this.phStatus,
    required this.turbidityRaw,
    required this.turbidityStatus,
    required this.tdsRaw,
    required this.tdsStatus,
    required this.overallStatus,
    required this.isOnline,
    required this.updatedAt,
  });

  final double temperatureC;
  final String tempStatus;
  final double ph;
  final String phStatus;
  final int turbidityRaw;
  final String turbidityStatus;
  final int tdsRaw;
  final String tdsStatus;
  final String overallStatus;
  final bool isOnline;
  final DateTime updatedAt;

  int get healthPercent {
    final statuses = [tempStatus, phStatus, turbidityStatus, tdsStatus];
    var score = 100;
    for (final status in statuses) {
      score -= switch (status) {
        'NORMAL' || 'CLEAR' => 0,
        'LOW' || 'HIGH' || 'MODERATE' => 12,
        'CRITICAL' || 'DIRTY' || 'NO SENSOR' => 24,
        _ => 8,
      };
    }
    if (!isOnline) score -= 18;
    return score.clamp(0, 100);
  }

  ReadingState get overallState {
    if (!isOnline || overallStatus == 'CRITICAL') return ReadingState.critical;
    if (overallStatus == 'MONITOR') return ReadingState.warning;
    return ReadingState.normal;
  }
}

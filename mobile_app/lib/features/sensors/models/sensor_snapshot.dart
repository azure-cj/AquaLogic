import 'package:aqualogic/shared/models/aqualogic_status.dart';
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

  OperationalStatus get operationalStatus {
    if (!isOnline) return OperationalStatus.offline;
    return switch (overallStatus.trim().toUpperCase()) {
      'CRITICAL' => OperationalStatus.critical,
      'MONITOR' || 'WARNING' => OperationalStatus.warning,
      _ => OperationalStatus.normal,
    };
  }

  ReadingState get overallState {
    return switch (operationalStatus) {
      OperationalStatus.normal => ReadingState.normal,
      OperationalStatus.warning => ReadingState.warning,
      OperationalStatus.critical => ReadingState.critical,
      OperationalStatus.offline => ReadingState.offline,
    };
  }
}

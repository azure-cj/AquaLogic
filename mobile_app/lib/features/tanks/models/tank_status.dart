import 'package:aqualogic/shared/models/reading_state.dart';
import 'package:aqualogic/shared/models/aqualogic_status.dart';

ReadingState tankStatusState(String status) {
  return switch (status.trim().toUpperCase()) {
    'NORMAL' => ReadingState.normal,
    'OFFLINE' => ReadingState.offline,
    'CRITICAL' => ReadingState.critical,
    _ => ReadingState.warning,
  };
}

OperationalStatus operationalStatusFromCode(String status) {
  return switch (status.trim().toLowerCase()) {
    'normal' => OperationalStatus.normal,
    'warning' || 'monitor' => OperationalStatus.warning,
    'critical' => OperationalStatus.critical,
    'offline' => OperationalStatus.offline,
    _ => throw FormatException('Unknown tank operational status: $status'),
  };
}

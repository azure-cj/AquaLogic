import 'package:aqualogic/features/alerts/models/alert_info.dart';

class AlertContextReading {
  const AlertContextReading({
    required this.id,
    required this.value,
    required this.unit,
    required this.observedAt,
    required this.receivedAt,
    required this.reportingFreshness,
  });
  final int id;
  final double? value;
  final String unit;
  final DateTime observedAt;
  final DateTime receivedAt;
  final String reportingFreshness;
}

class AlertContextThreshold {
  const AlertContextThreshold({
    required this.unit,
    required this.warningMin,
    required this.warningMax,
    required this.criticalMin,
    required this.criticalMax,
    required this.enabled,
    required this.source,
  });
  final String unit;
  final double? warningMin, warningMax, criticalMin, criticalMax;
  final bool enabled;
  final String source;
}

class AlertContext {
  const AlertContext({
    required this.alert,
    required this.tankLifecycle,
    required this.evaluatedAt,
    required this.linkedReading,
    required this.latestReading,
    required this.linkedThreshold,
    required this.currentThreshold,
    required this.code,
    required this.direction,
    required this.explanation,
    required this.checks,
    required this.advisory,
    this.speciesContext,
  });
  final AlertInfo alert;
  final String tankLifecycle;
  final DateTime evaluatedAt;
  final AlertContextReading? linkedReading, latestReading;
  final AlertContextThreshold? linkedThreshold, currentThreshold;
  final String code, direction, explanation, advisory;
  final List<String> checks;
  final AlertSpeciesContext? speciesContext;
}

class AlertSpeciesPreference {
  const AlertSpeciesPreference({
    required this.id,
    required this.name,
    required this.minimum,
    required this.maximum,
    required this.result,
    required this.reason,
  });
  final int id;
  final String name, result, reason;
  final double? minimum, maximum;
}

class AlertSpeciesContext {
  const AlertSpeciesContext({
    required this.parameter,
    required this.status,
    required this.reason,
    required this.unit,
    required this.readingId,
    required this.observedAt,
    required this.receivedAt,
    required this.counts,
    required this.species,
    required this.advisory,
  });
  final String parameter, status, unit, advisory;
  final String? reason;
  final int? readingId;
  final DateTime? observedAt, receivedAt;
  final Map<String, int> counts;
  final List<AlertSpeciesPreference> species;
}

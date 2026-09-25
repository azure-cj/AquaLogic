import 'package:aqualogic/shared/models/aqualogic_status.dart';
import 'package:aqualogic/features/tanks/models/tank_status.dart';

enum TankLifecycle { active, retired }

enum SensorParameter {
  temperature,
  ph,
  turbidity,
  tds;

  String get label => switch (this) {
    SensorParameter.temperature => 'Temperature',
    SensorParameter.ph => 'pH',
    SensorParameter.turbidity => 'Turbidity',
    SensorParameter.tds => 'TDS',
  };
}

enum ReadingCondition {
  normal,
  warning,
  critical,
  stale,
  unavailable;

  String get label => switch (this) {
    ReadingCondition.normal => 'Normal',
    ReadingCondition.warning => 'Warning',
    ReadingCondition.critical => 'Critical',
    ReadingCondition.stale => 'Last known',
    ReadingCondition.unavailable => 'Unavailable',
  };
}

enum TankIssueCategory { waterQuality, monitoring }

enum TankIssueSeverity { info, warning, critical }

enum TankIssueLifecycle { active, handled, recovered }

class TankReading {
  const TankReading({
    required this.parameter,
    required this.value,
    required this.unit,
    required this.condition,
    required this.timestampLabel,
    this.note,
    this.observedAt,
    this.receivedAt,
    this.isMock = false,
  });

  final SensorParameter parameter;
  final String value;
  final String unit;
  final ReadingCondition condition;
  final String timestampLabel;
  final String? note;
  final DateTime? observedAt;
  final DateTime? receivedAt;
  final bool isMock;

  /// A reading can have a valid numeric value even when the backend cannot
  /// evaluate its threshold state. Missing values remain explicitly absent.
  bool get isAvailable => value.trim().isNotEmpty && value != '—';
}

class TankIssue {
  const TankIssue({
    required this.id,
    required this.category,
    required this.severity,
    required this.title,
    required this.message,
    required this.timeLabel,
    required this.lifecycle,
    this.sourceId,
  });

  final String id;
  final TankIssueCategory category;
  final TankIssueSeverity severity;
  final String title;
  final String message;
  final String timeLabel;
  final TankIssueLifecycle lifecycle;
  final String? sourceId;

  bool get isActive => lifecycle == TankIssueLifecycle.active;
}

class TankSpeciesSummary {
  const TankSpeciesSummary({
    required this.speciesId,
    required this.name,
    required this.suitability,
    this.count,
  });

  final String speciesId;
  final String name;
  final SpeciesSuitability suitability;
  final int? count;
}

class TankActivity {
  const TankActivity({
    required this.id,
    required this.title,
    required this.detail,
    required this.timeLabel,
  });

  final String id;
  final String title;
  final String detail;
  final String timeLabel;
}

/// Presentation model for a tank. The legacy fields remain available to keep
/// older local Home fixtures source-compatible, while the optional fields
/// expose backend-shaped operational concepts to the newer screens.
class TankInfo {
  const TankInfo({
    required this.initial,
    required this.name,
    required this.subtitle,
    required this.status,
    required this.typeLabel,
    required this.volumeLabel,
    required this.lastFedLabel,
    required this.description,
    this.isSelected = false,
    this.id,
    this.locationLabel,
    this.lastReportLabel = 'Updated just now',
    this.lastReportedAt,
    this.reportingAgeSeconds,
    this.latestCondition,
    this.monitoringLabel = 'Reporting normally',
    this.lifecycle = TankLifecycle.active,
    this.readings = const <TankReading>[],
    this.issues = const <TankIssue>[],
    this.species = const <TankSpeciesSummary>[],
    this.equipmentCount = 0,
    this.recentActivity = const <TankActivity>[],
    this.isLiveData = false,
    this.operationsAvailable = true,
    this.monitoringAvailable = true,
    this.suitabilityAvailable = true,
    this.assignedSpeciesCount,
  });

  final String initial;
  final String name;
  final String subtitle;
  final String status;
  final String typeLabel;
  final String volumeLabel;
  final String lastFedLabel;
  final String description;
  final bool isSelected;

  final String? id;
  final String? locationLabel;
  final String lastReportLabel;
  final DateTime? lastReportedAt;
  final int? reportingAgeSeconds;
  final String? latestCondition;
  final String monitoringLabel;
  final TankLifecycle lifecycle;
  final List<TankReading> readings;
  final List<TankIssue> issues;
  final List<TankSpeciesSummary> species;
  final int equipmentCount;
  final List<TankActivity> recentActivity;
  final bool isLiveData;
  final bool operationsAvailable;
  final bool monitoringAvailable;
  final bool suitabilityAvailable;
  final int? assignedSpeciesCount;

  String get tankId => id ?? _slugify(name);

  bool get isRetired => lifecycle == TankLifecycle.retired;

  String get locationOrType =>
      locationLabel == null || locationLabel!.trim().isEmpty
      ? typeLabel
      : locationLabel!;

  OperationalStatus get operationalStatus {
    return switch (status.trim().toLowerCase()) {
      'good' => OperationalStatus.normal,
      _ => operationalStatusFromCode(status),
    };
  }

  String get lifecycleLabel =>
      lifecycle == TankLifecycle.retired ? 'Retired' : 'Active';

  TankInfo copyWith({
    String? initial,
    String? name,
    String? subtitle,
    String? status,
    String? typeLabel,
    String? volumeLabel,
    String? lastFedLabel,
    String? description,
    bool? isSelected,
    String? id,
    String? locationLabel,
    String? lastReportLabel,
    DateTime? lastReportedAt,
    int? reportingAgeSeconds,
    String? latestCondition,
    String? monitoringLabel,
    TankLifecycle? lifecycle,
    List<TankReading>? readings,
    List<TankIssue>? issues,
    List<TankSpeciesSummary>? species,
    int? equipmentCount,
    List<TankActivity>? recentActivity,
    bool? isLiveData,
    bool? operationsAvailable,
    bool? monitoringAvailable,
    bool? suitabilityAvailable,
    int? assignedSpeciesCount,
  }) {
    return TankInfo(
      initial: initial ?? this.initial,
      name: name ?? this.name,
      subtitle: subtitle ?? this.subtitle,
      status: status ?? this.status,
      typeLabel: typeLabel ?? this.typeLabel,
      volumeLabel: volumeLabel ?? this.volumeLabel,
      lastFedLabel: lastFedLabel ?? this.lastFedLabel,
      description: description ?? this.description,
      isSelected: isSelected ?? this.isSelected,
      id: id ?? this.id,
      locationLabel: locationLabel ?? this.locationLabel,
      lastReportLabel: lastReportLabel ?? this.lastReportLabel,
      lastReportedAt: lastReportedAt ?? this.lastReportedAt,
      reportingAgeSeconds: reportingAgeSeconds ?? this.reportingAgeSeconds,
      latestCondition: latestCondition ?? this.latestCondition,
      monitoringLabel: monitoringLabel ?? this.monitoringLabel,
      lifecycle: lifecycle ?? this.lifecycle,
      readings: readings ?? this.readings,
      issues: issues ?? this.issues,
      species: species ?? this.species,
      equipmentCount: equipmentCount ?? this.equipmentCount,
      recentActivity: recentActivity ?? this.recentActivity,
      isLiveData: isLiveData ?? this.isLiveData,
      operationsAvailable: operationsAvailable ?? this.operationsAvailable,
      monitoringAvailable: monitoringAvailable ?? this.monitoringAvailable,
      suitabilityAvailable: suitabilityAvailable ?? this.suitabilityAvailable,
      assignedSpeciesCount: assignedSpeciesCount ?? this.assignedSpeciesCount,
    );
  }
}

String _slugify(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
}

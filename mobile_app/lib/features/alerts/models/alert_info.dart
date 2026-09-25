import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

enum AlertCategory { waterQuality, monitoring }

enum AlertSeverity { warning, critical }

enum AlertLifecycle { active, handled, resolvedAutomatically, resolved }

enum AlertResolutionSource { operator, system, unknown }

class AlertInfo {
  const AlertInfo({
    required this.id,
    required this.tankId,
    required this.tankName,
    required this.parameter,
    required this.severity,
    required this.message,
    required this.startedLabel,
    required this.lifecycle,
    this.readingId,
    this.startedAt,
    this.resolvedAt,
    this.resolvedByUserId,
    this.resolutionSource,
    this.recommendation,
    this.icon = LucideIcons.triangleAlert,
  });

  final String id;
  final String tankId;
  final String tankName;
  final String parameter;
  final AlertSeverity severity;
  final String message;
  final String startedLabel;
  final AlertLifecycle lifecycle;
  final int? readingId;
  final DateTime? startedAt;
  final DateTime? resolvedAt;
  final int? resolvedByUserId;
  final AlertResolutionSource? resolutionSource;
  final String? recommendation;
  final IconData icon;

  AlertCategory get category => AlertCategory.waterQuality;
  bool get isActive => lifecycle == AlertLifecycle.active;
  String get statusLabel => switch (lifecycle) {
    AlertLifecycle.active => 'Active',
    AlertLifecycle.handled => 'Handled',
    AlertLifecycle.resolvedAutomatically => 'Resolved automatically',
    AlertLifecycle.resolved => 'Resolved',
  };
  String get title => '$parameter alert';
  String get time => startedLabel;

  AlertInfo copyWith({
    AlertLifecycle? lifecycle,
    DateTime? resolvedAt,
    int? resolvedByUserId,
    AlertResolutionSource? resolutionSource,
  }) {
    return AlertInfo(
      id: id,
      tankId: tankId,
      tankName: tankName,
      parameter: parameter,
      severity: severity,
      message: message,
      startedLabel: startedLabel,
      lifecycle: lifecycle ?? this.lifecycle,
      readingId: readingId,
      startedAt: startedAt,
      resolvedAt: resolvedAt ?? this.resolvedAt,
      resolvedByUserId: resolvedByUserId ?? this.resolvedByUserId,
      resolutionSource: resolutionSource ?? this.resolutionSource,
      recommendation: recommendation,
      icon: icon,
    );
  }
}

class MonitoringIncident {
  const MonitoringIncident({
    required this.id,
    required this.tankId,
    required this.tankName,
    required this.message,
    required this.startedLabel,
    required this.status,
    this.startedAt,
    this.detectedAt,
    this.resolvedAt,
    this.lastReadingReceivedAt,
    this.lastReportAgeSeconds,
    this.durationSeconds,
    this.resolutionReason,
    this.recoveredLabel,
  });

  final String id;
  final String tankId;
  final String tankName;
  final String message;
  final String startedLabel;
  final MonitoringIncidentStatus status;
  final DateTime? startedAt;
  final DateTime? detectedAt;
  final DateTime? resolvedAt;
  final DateTime? lastReadingReceivedAt;
  final int? lastReportAgeSeconds;
  final int? durationSeconds;
  final MonitoringResolutionReason? resolutionReason;
  final String? recoveredLabel;

  bool get isActive => status == MonitoringIncidentStatus.active;

  String get lifecycleLabel {
    if (isActive) return 'Offline';
    return switch (resolutionReason) {
      MonitoringResolutionReason.reportingRecovered => 'Recovered',
      MonitoringResolutionReason.monitoringDisabled => 'Monitoring disabled',
      MonitoringResolutionReason.tankRetired => 'Tank retired',
      MonitoringResolutionReason.unknown || null => 'Resolved',
    };
  }

  String get resolutionMessage => switch (resolutionReason) {
    MonitoringResolutionReason.reportingRecovered =>
      'Reporting recovered and a new reading was received.',
    MonitoringResolutionReason.monitoringDisabled =>
      'Monitoring was disabled for this tank.',
    MonitoringResolutionReason.tankRetired =>
      'This tank was retired; reporting is no longer expected.',
    MonitoringResolutionReason.unknown ||
    null => 'This monitoring incident is resolved.',
  };
}

enum MonitoringIncidentStatus { active, resolved }

enum MonitoringResolutionReason {
  reportingRecovered,
  monitoringDisabled,
  tankRetired,
  unknown,
}

class MonitoringIncidentPage {
  const MonitoringIncidentPage({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.total,
    required this.totalPages,
    required this.hasNext,
  });

  final List<MonitoringIncident> items;
  final int page;
  final int pageSize;
  final int total;
  final int totalPages;
  final bool hasNext;
}

class AlertCenterData {
  const AlertCenterData({
    required this.waterQualityAlerts,
    required this.monitoringIncidents,
  });

  final List<AlertInfo> waterQualityAlerts;
  final List<MonitoringIncident> monitoringIncidents;

  List<AlertInfo> get activeWaterQualityAlerts => waterQualityAlerts
      .where((alert) => alert.isActive)
      .toList(growable: false);

  List<AlertInfo> get handledWaterQualityAlerts => waterQualityAlerts
      .where((alert) => !alert.isActive)
      .toList(growable: false);

  List<MonitoringIncident> get activeMonitoringIncidents => monitoringIncidents
      .where((incident) => incident.isActive)
      .toList(growable: false);

  List<MonitoringIncident> get historicalMonitoringIncidents =>
      monitoringIncidents
          .where((incident) => !incident.isActive)
          .toList(growable: false);

  int get criticalCount => activeWaterQualityAlerts
      .where((alert) => alert.severity == AlertSeverity.critical)
      .length;

  int get warningCount => activeWaterQualityAlerts
      .where((alert) => alert.severity == AlertSeverity.warning)
      .length;
}

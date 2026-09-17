import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

enum AlertCategory { waterQuality, monitoring }

enum AlertSeverity { warning, critical }

enum AlertLifecycle { active, handled }

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
  final String? recommendation;
  final IconData icon;

  AlertCategory get category => AlertCategory.waterQuality;
  bool get isActive => lifecycle == AlertLifecycle.active;
  String get title => '$parameter alert';
  String get time => startedLabel;
  String get statusLabel => isActive ? 'Active' : 'Handled';

  AlertInfo copyWith({AlertLifecycle? lifecycle}) {
    return AlertInfo(
      id: id,
      tankId: tankId,
      tankName: tankName,
      parameter: parameter,
      severity: severity,
      message: message,
      startedLabel: startedLabel,
      lifecycle: lifecycle ?? this.lifecycle,
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
    this.recoveredLabel,
  });

  final String id;
  final String tankId;
  final String tankName;
  final String message;
  final String startedLabel;
  final MonitoringIncidentStatus status;
  final String? recoveredLabel;

  bool get isActive => status == MonitoringIncidentStatus.active;
}

enum MonitoringIncidentStatus { active, recovered }

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

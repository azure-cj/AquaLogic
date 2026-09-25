import 'package:aqualogic/features/alerts/models/alert_info.dart';
import 'package:aqualogic/features/demo/demo_data.dart';
import 'package:aqualogic/features/sensors/data/mock_sensor_feed.dart';
import 'package:aqualogic/features/sensors/models/sensor_snapshot.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

abstract class AlertRepository {
  Future<List<AlertInfo>> loadWaterQualityAlerts({
    required SensorSnapshot snapshot,
    required bool history,
  });

  Future<MonitoringIncidentPage> loadMonitoringIncidents({
    required SensorSnapshot snapshot,
    required bool history,
    required int page,
    int pageSize = 25,
  });

  Future<AlertInfo?> findWaterQualityAlert({
    required SensorSnapshot snapshot,
    required String alertId,
  });

  Future<MonitoringIncident?> findMonitoringIncident({
    required SensorSnapshot snapshot,
    required String incidentId,
    required bool history,
  });

  Future<AlertInfo> resolveAlert(String alertId);
}

/// Deterministic local alert fixtures. The fixture builder remains synchronous
/// for other demo-only surfaces; repository operations themselves are async so
/// mock and API implementations share the same screen loading contract.
class MockAlertRepository implements AlertRepository {
  const MockAlertRepository({this.monitoringOutageTankIds = const <String>{}});

  final Set<String> monitoringOutageTankIds;

  @override
  Future<List<AlertInfo>> loadWaterQualityAlerts({
    required SensorSnapshot snapshot,
    required bool history,
  }) async {
    final data = buildMockAlertCenterData(
      snapshot: snapshot,
      monitoringOutageTankIds: monitoringOutageTankIds,
    );
    return data.waterQualityAlerts
        .where((alert) => history ? !alert.isActive : alert.isActive)
        .toList(growable: false);
  }

  @override
  Future<MonitoringIncidentPage> loadMonitoringIncidents({
    required SensorSnapshot snapshot,
    required bool history,
    required int page,
    int pageSize = 25,
  }) async {
    final data = buildMockAlertCenterData(
      snapshot: snapshot,
      monitoringOutageTankIds: monitoringOutageTankIds,
    );
    final allItems = data.monitoringIncidents
        .where((incident) => history ? !incident.isActive : incident.isActive)
        .toList(growable: false);
    final start = (page - 1) * pageSize;
    final end = (start + pageSize).clamp(0, allItems.length);
    final items = start >= allItems.length
        ? const <MonitoringIncident>[]
        : allItems.sublist(start, end);
    final totalPages = (allItems.length + pageSize - 1) ~/ pageSize;
    return MonitoringIncidentPage(
      items: items,
      page: page,
      pageSize: pageSize,
      total: allItems.length,
      totalPages: totalPages,
      hasNext: page < totalPages,
    );
  }

  @override
  Future<AlertInfo?> findWaterQualityAlert({
    required SensorSnapshot snapshot,
    required String alertId,
  }) async {
    for (final alert in buildMockAlertCenterData(
      snapshot: snapshot,
      monitoringOutageTankIds: monitoringOutageTankIds,
    ).waterQualityAlerts) {
      if (alert.id == alertId) return alert;
    }
    return null;
  }

  @override
  Future<MonitoringIncident?> findMonitoringIncident({
    required SensorSnapshot snapshot,
    required String incidentId,
    required bool history,
  }) async {
    for (final incident in buildMockAlertCenterData(
      snapshot: snapshot,
      monitoringOutageTankIds: monitoringOutageTankIds,
    ).monitoringIncidents) {
      if (incident.id == incidentId && incident.isActive != history) {
        return incident;
      }
    }
    return null;
  }

  @override
  Future<AlertInfo> resolveAlert(String alertId) async {
    final alert = await findWaterQualityAlert(
      snapshot: MockSensorFeed.snapshot(0),
      alertId: alertId,
    );
    if (alert == null) {
      throw StateError('Mock alert not found.');
    }
    return alert.copyWith(
      lifecycle: AlertLifecycle.handled,
      resolvedAt: DateTime.now().toUtc(),
      resolutionSource: AlertResolutionSource.operator,
    );
  }
}

AlertCenterData buildMockAlertCenterData({
  required SensorSnapshot snapshot,
  Set<String> monitoringOutageTankIds = const <String>{},
}) {
  final waterQuality = <AlertInfo>[
    if (snapshot.isOnline) ...[
      const AlertInfo(
        id: 'freshwater-c-tds',
        tankId: 'freshwater-c',
        tankName: 'Freshwater C',
        parameter: 'TDS',
        severity: AlertSeverity.critical,
        message: 'TDS is outside the configured range.',
        startedLabel: 'Started 18 min ago',
        lifecycle: AlertLifecycle.active,
        recommendation: 'Review the tank before the next water change.',
        icon: LucideIcons.circleAlert,
      ),
      const AlertInfo(
        id: 'quarantine-b-ph',
        tankId: 'quarantine-b',
        tankName: 'Quarantine B',
        parameter: 'pH',
        severity: AlertSeverity.warning,
        message: 'pH requires attention in the quarantine range.',
        startedLabel: 'Started 6 min ago',
        lifecycle: AlertLifecycle.active,
        recommendation: 'Review the latest reading.',
        icon: LucideIcons.triangleAlert,
      ),
    ],
    const AlertInfo(
      id: 'display-reef-a-temp-history',
      tankId: 'display-reef-a',
      tankName: 'Display Reef A',
      parameter: 'Temperature',
      severity: AlertSeverity.warning,
      message: 'Temperature returned to the configured range.',
      startedLabel: 'Resolved automatically 2h ago',
      lifecycle: AlertLifecycle.resolvedAutomatically,
      resolutionSource: AlertResolutionSource.system,
      icon: LucideIcons.circleCheck,
    ),
  ];

  final monitoringIds = monitoringOutageTankIds.isNotEmpty
      ? monitoringOutageTankIds
      : snapshot.isOnline
      ? const <String>{}
      : DemoData.tanks.map((tank) => tank.tankId).toSet();
  final monitoring = <MonitoringIncident>[
    for (final tank in DemoData.tanks)
      if (monitoringIds.contains(tank.tankId))
        MonitoringIncident(
          id: '${tank.tankId}-monitoring',
          tankId: tank.tankId,
          tankName: tank.name,
          message: 'No recent readings received.',
          startedLabel: 'Started 12 min ago',
          status: MonitoringIncidentStatus.active,
        ),
    const MonitoringIncident(
      id: 'display-reef-a-monitoring-history',
      tankId: 'display-reef-a',
      tankName: 'Display Reef A',
      message: 'Reporting recovered and a new reading was received.',
      startedLabel: 'Started yesterday',
      status: MonitoringIncidentStatus.resolved,
      resolutionReason: MonitoringResolutionReason.reportingRecovered,
      recoveredLabel: 'Recovered 20h ago',
    ),
  ];

  return AlertCenterData(
    waterQualityAlerts: waterQuality,
    monitoringIncidents: monitoring,
  );
}

import 'package:aqualogic/features/alerts/models/alert_info.dart';
import 'package:aqualogic/features/demo/demo_data.dart';
import 'package:aqualogic/features/sensors/models/sensor_snapshot.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

abstract class AlertRepository {
  AlertCenterData load({required SensorSnapshot snapshot});
}

/// Deterministic local alert fixtures. The shape mirrors the future alert and
/// monitoring-incident responses without introducing HTTP into the prototype.
class MockAlertRepository implements AlertRepository {
  const MockAlertRepository({this.monitoringOutageTankIds = const <String>{}});

  final Set<String> monitoringOutageTankIds;

  @override
  AlertCenterData load({required SensorSnapshot snapshot}) {
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
        startedLabel: 'Handled 2h ago',
        lifecycle: AlertLifecycle.handled,
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
        message: 'Reporting interruption recovered.',
        startedLabel: 'Started yesterday',
        status: MonitoringIncidentStatus.recovered,
        recoveredLabel: 'Recovered 20h ago',
      ),
    ];

    return AlertCenterData(
      waterQualityAlerts: waterQuality,
      monitoringIncidents: monitoring,
    );
  }
}

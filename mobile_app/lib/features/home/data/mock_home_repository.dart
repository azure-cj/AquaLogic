import 'package:aqualogic/features/alerts/data/mock_alert_repository.dart';
import 'package:aqualogic/features/alerts/models/alert_info.dart';
import 'package:aqualogic/features/demo/demo_data.dart';
import 'package:aqualogic/features/home/models/home_dashboard_data.dart';
import 'package:aqualogic/features/sensors/models/sensor_snapshot.dart';

abstract class HomeRepository {
  HomeDashboardData load({required SensorSnapshot snapshot});
}

/// Local Home composition data. This is the seam for a future API repository.
class MockHomeRepository implements HomeRepository {
  const MockHomeRepository({this.offlineTankIds = const <String>{}});

  /// Optional fixture override used to exercise the distinct offline state.
  final Set<String> offlineTankIds;

  @override
  HomeDashboardData load({required SensorSnapshot snapshot}) {
    final alertData = MockAlertRepository(
      monitoringOutageTankIds: snapshot.isOnline ? offlineTankIds : const {},
    ).load(snapshot: snapshot);
    final tanks = DemoData.tanks
        .map((tank) {
          final id = _tankId(tank.name);
          final status = !snapshot.isOnline || offlineTankIds.contains(id)
              ? HomeOperationalStatus.offline
              : _operationalStatus(tank.status);
          final isReporting = status != HomeOperationalStatus.offline;

          return HomeTankSummary(
            id: id,
            initial: tank.initial,
            name: tank.name,
            subtitle: tank.subtitle,
            status: status,
            lastReportedAt: isReporting ? snapshot.updatedAt : null,
            lastReportLabel: isReporting
                ? 'Updated just now'
                : 'No recent report',
            contextLabel: _contextLabel(status),
          );
        })
        .toList(growable: false);

    final attentionItems =
        tanks
            .where((tank) => tank.status.requiresAttention)
            .map((tank) => _attentionFor(tank, alertData))
            .toList()
          ..sort(
            (left, right) =>
                left.status.priority.compareTo(right.status.priority),
          );

    return HomeDashboardData(
      tanks: tanks,
      attentionItems: attentionItems,
      monitoring: HomeMonitoringSummary(
        totalTankCount: tanks.length,
        reportingTankCount: tanks
            .where((tank) => tank.status != HomeOperationalStatus.offline)
            .length,
        outageCount: tanks
            .where((tank) => tank.status == HomeOperationalStatus.offline)
            .length,
        sensorFeedOnline: snapshot.isOnline,
      ),
      recentActivity: [
        HomeActivityItem(
          id: 'feeding-display-reef-a',
          title: 'Feeding completed',
          tankName: DemoData.tanks.first.name,
          timeLabel: '8:30 AM',
          type: HomeActivityType.feeding,
        ),
        HomeActivityItem(
          id: 'uv-nursery-d',
          title: 'UV cycle completed',
          tankName: DemoData.tanks.last.name,
          timeLabel: '7:45 AM',
          type: HomeActivityType.uvCycle,
        ),
      ],
    );
  }

  HomeAttentionItem _attentionFor(
    HomeTankSummary tank,
    AlertCenterData alertData,
  ) {
    final isOffline = tank.status == HomeOperationalStatus.offline;
    final sourceId = isOffline
        ? _monitoringSourceId(tank.id, alertData)
        : _waterQualitySourceId(tank.id, alertData);
    return HomeAttentionItem(
      id: '${tank.id}-${tank.status.name}',
      tankId: tank.id,
      tankName: tank.name,
      type: isOffline
          ? HomeAttentionType.monitoring
          : HomeAttentionType.waterQuality,
      status: tank.status,
      title: isOffline
          ? 'No recent readings'
          : '${tank.status.label} water-quality state',
      message: isOffline
          ? 'Monitoring has no recent report from this tank.'
          : 'Latest readings need review before the next routine check.',
      actionLabel: isOffline ? 'View tank' : 'View alert',
      sourceId: sourceId,
    );
  }

  String? _waterQualitySourceId(String tankId, AlertCenterData alertData) {
    for (final alert in alertData.waterQualityAlerts) {
      if (alert.tankId == tankId && alert.isActive) return alert.id;
    }
    return null;
  }

  String? _monitoringSourceId(String tankId, AlertCenterData alertData) {
    for (final incident in alertData.monitoringIncidents) {
      if (incident.tankId == tankId && incident.isActive) return incident.id;
    }
    return null;
  }

  HomeOperationalStatus _operationalStatus(String status) {
    return switch (status.trim().toUpperCase()) {
      'NORMAL' || 'GOOD' => HomeOperationalStatus.normal,
      'WARNING' || 'MONITOR' => HomeOperationalStatus.warning,
      'CRITICAL' => HomeOperationalStatus.critical,
      'OFFLINE' => HomeOperationalStatus.offline,
      // Unrecognized local data is not safe to present as a warning.
      _ => HomeOperationalStatus.offline,
    };
  }

  String _contextLabel(HomeOperationalStatus status) {
    return switch (status) {
      HomeOperationalStatus.normal => 'Ready for routine checks',
      HomeOperationalStatus.warning => 'Review latest readings',
      HomeOperationalStatus.critical => 'Action recommended',
      HomeOperationalStatus.offline => 'No recent readings',
    };
  }

  String _tankId(String name) {
    return name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
  }
}

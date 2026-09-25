import 'package:aqualogic/features/home/data/api_home_models.dart';
import 'package:aqualogic/features/home/data/home_repository.dart';
import 'package:aqualogic/features/home/models/home_dashboard_data.dart';
import 'package:aqualogic/shared/network/api_client.dart';
import 'package:aqualogic/shared/network/api_failure.dart';

/// Home's read-only production composition over the existing authenticated
/// client. `/fleet` is required; alerts and incident details are independent
/// secondary sources so a partial outage does not discard fleet data.
class ApiHomeRepository extends HomeRepository {
  ApiHomeRepository({required this.apiClient});

  static const fleetPath = '/fleet';
  static const alertsPath = '/alerts';
  static const monitoringIncidentsPath =
      '/monitoring-incidents?state=active&page=1&page_size=100';

  final ApiClient apiClient;

  @override
  bool get isLiveData => true;

  @override
  Future<HomeDashboardData> load() async {
    final fleetRequest = _capture(() async {
      final response = await apiClient.get(fleetPath, authenticated: true);
      final body = response.body;
      if (body is! List) throw const FormatException('Expected fleet list.');
      return body.map(FleetTankDto.fromJson).toList(growable: false);
    });
    final alertsRequest = _capture(() async {
      final response = await apiClient.get(alertsPath, authenticated: true);
      final body = response.body;
      if (body is! List) throw const FormatException('Expected alert list.');
      return body.map(HomeAlertDto.fromJson).toList(growable: false);
    });
    final incidentsRequest = _capture(() async {
      final response = await apiClient.get(
        monitoringIncidentsPath,
        authenticated: true,
      );
      return MonitoringIncidentPageDto.fromJson(response.body);
    });

    final results = await Future.wait<Object>([
      fleetRequest,
      alertsRequest,
      incidentsRequest,
    ]);
    final fleetResult = results[0] as _LoadResult<List<FleetTankDto>>;
    final alertsResult = results[1] as _LoadResult<List<HomeAlertDto>>;
    final incidentsResult =
        results[2] as _LoadResult<MonitoringIncidentPageDto>;
    final fleet = fleetResult.value;
    if (fleet == null) throw fleetResult.failure ?? _unreadableHomeFailure();

    final tanksById = <int, FleetTankDto>{};
    final homeTanksById = <int, HomeTankSummary>{};
    for (final tank in fleet) {
      tanksById[tank.id] = tank;
      homeTanksById[tank.id] = _mapTank(tank);
    }
    final tanks = homeTanksById.values.toList(growable: false);
    final alerts = alertsResult.value ?? const <HomeAlertDto>[];
    final incidentPage = incidentsResult.value;
    final activeIncidents =
        incidentPage?.items
            .where(
              (incident) =>
                  incident.state == 'active' &&
                  incident.tankLifecycle == 'active',
            )
            .toList(growable: false) ??
        const <MonitoringIncidentDto>[];
    final activeIncidentByTank = {
      for (final incident in activeIncidents) incident.tankId: incident,
    };

    final attentionItems = <HomeAttentionItem>[];
    final tanksWithWaterAlerts = <int>{};
    for (final alert in alerts.where((item) => !item.isResolved)) {
      final tank = tanksById[alert.tankId];
      if (tank == null) continue;
      final status = _alertStatus(alert.severity);
      if (status == null) continue;
      tanksWithWaterAlerts.add(alert.tankId);
      attentionItems.add(
        HomeAttentionItem(
          id: 'water-alert-${alert.id}',
          tankId: alert.tankId.toString(),
          tankName: tank.name,
          type: HomeAttentionType.waterQuality,
          status: status,
          title: '${status.label} ${_parameterLabel(alert.parameter)} reading',
          message: alert.message.trim().isEmpty
              ? 'An active water-quality alert needs review.'
              : alert.message,
          actionLabel: 'Details in M4',
          sourceId: alert.id.toString(),
          occurredAt: alert.createdAt,
        ),
      );
    }

    // Fleet status is also authoritative and prevents an empty priority area
    // when an alert record is temporarily absent or its endpoint is partial.
    for (final tank in fleet) {
      final status = _fleetStatus(tank.status);
      if ((status == HomeOperationalStatus.warning ||
              status == HomeOperationalStatus.critical) &&
          !tanksWithWaterAlerts.contains(tank.id)) {
        attentionItems.add(
          HomeAttentionItem(
            id: 'fleet-water-status-${tank.id}',
            tankId: tank.id.toString(),
            tankName: tank.name,
            type: HomeAttentionType.waterQuality,
            status: status,
            title: '${status.label} water-quality status',
            message: 'The backend fleet status requires a review.',
            actionLabel: 'Details in M4',
          ),
        );
      }
    }

    final offlineFleetIds = <int>{};
    for (final tank in fleet) {
      if (_fleetStatus(tank.status) != HomeOperationalStatus.offline) continue;
      offlineFleetIds.add(tank.id);
      final incident = activeIncidentByTank.remove(tank.id);
      attentionItems.add(
        incident == null
            ? _offlineFleetItem(tank)
            : _monitoringIncidentItem(incident, tank.name),
      );
    }
    for (final incident in activeIncidentByTank.values) {
      final tank = homeTanksById[incident.tankId];
      if (tank != null && !offlineFleetIds.contains(incident.tankId)) {
        attentionItems.add(_monitoringIncidentItem(incident, tank.name));
      }
    }
    attentionItems.sort(_compareAttention);

    final incidentCount =
        incidentPage?.total ??
        fleet.fold<int>(
          0,
          (total, tank) => total + tank.activeMonitoringIncidentCount,
        );
    final now = DateTime.now().toUtc();
    return HomeDashboardData(
      tanks: tanks,
      attentionItems: attentionItems,
      monitoring: HomeMonitoringSummary(
        totalTankCount: tanks.length,
        reportingTankCount: tanks
            .where((tank) => tank.status != HomeOperationalStatus.offline)
            .length,
        outageCount: incidentCount,
        incidentDetailsAvailable: incidentsResult.value != null,
      ),
      recentActivity: const [],
      alertsAvailable: alertsResult.value != null,
      monitoringIncidentsAvailable: incidentsResult.value != null,
      loadedAt: now,
      isLiveData: true,
    );
  }

  static HomeTankSummary _mapTank(FleetTankDto tank) {
    final status = _fleetStatus(tank.status);
    final age = tank.reportingAgeSeconds;
    return HomeTankSummary(
      id: tank.id.toString(),
      initial: tank.name.trim().isEmpty
          ? 'T'
          : tank.name.trim().substring(0, 1).toUpperCase(),
      name: tank.name,
      subtitle: tank.location,
      status: status,
      lastReportedAt: tank.lastReadingAt,
      reportingAgeSeconds: age,
      lastReportLabel: _freshnessLabel(age, status),
      contextLabel: tank.location,
    );
  }

  static HomeAttentionItem _offlineFleetItem(FleetTankDto tank) {
    final age = tank.reportingAgeSeconds;
    return HomeAttentionItem(
      id: 'fleet-monitoring-${tank.id}',
      tankId: tank.id.toString(),
      tankName: tank.name,
      type: HomeAttentionType.monitoring,
      status: HomeOperationalStatus.offline,
      title: 'Tank reporting offline',
      message: age == null
          ? 'The backend fleet status reports no current sensor reading.'
          : 'The last report was received ${_durationLabel(age)} ago.',
      actionLabel: 'Details in M4',
      occurredAt: tank.lastReadingAt,
    );
  }

  static HomeAttentionItem _monitoringIncidentItem(
    MonitoringIncidentDto incident,
    String tankName,
  ) {
    final age = incident.lastReportAgeSeconds;
    return HomeAttentionItem(
      id: 'monitoring-incident-${incident.id}',
      tankId: incident.tankId.toString(),
      tankName: tankName,
      type: HomeAttentionType.monitoring,
      status: HomeOperationalStatus.offline,
      title: 'Tank reporting offline',
      message: age == null
          ? 'An active monitoring incident is recorded for this tank.'
          : 'The last report was received ${_durationLabel(age)} ago.',
      actionLabel: 'Details in M4',
      sourceId: incident.id.toString(),
      occurredAt: incident.detectedAt,
    );
  }

  static HomeOperationalStatus _fleetStatus(String value) =>
      switch (value.toLowerCase()) {
        'normal' => HomeOperationalStatus.normal,
        'warning' => HomeOperationalStatus.warning,
        'critical' => HomeOperationalStatus.critical,
        'offline' => HomeOperationalStatus.offline,
        _ => throw const ApiFailure(
          kind: ApiFailureKind.unknown,
          message: 'AquaLogic returned a fleet status that could not be read.',
          retryable: true,
        ),
      };

  static HomeOperationalStatus? _alertStatus(String value) =>
      switch (value.toLowerCase()) {
        'warning' => HomeOperationalStatus.warning,
        'critical' => HomeOperationalStatus.critical,
        _ => null,
      };

  static String _parameterLabel(String parameter) =>
      switch (parameter.toLowerCase()) {
        'temperature' => 'Temperature',
        'ph' => 'pH',
        'turbidity' => 'Turbidity',
        'dissolved_oxygen' => 'Dissolved oxygen',
        'tds' => 'TDS',
        'ammonia' => 'Ammonia',
        _ => parameter.replaceAll('_', ' '),
      };

  static String _freshnessLabel(
    int? reportingAgeSeconds,
    HomeOperationalStatus status,
  ) {
    if (status == HomeOperationalStatus.offline ||
        reportingAgeSeconds == null) {
      return 'No recent report';
    }
    if (reportingAgeSeconds < 60) return 'Updated just now';
    return 'Updated ${_durationLabel(reportingAgeSeconds)} ago';
  }

  static String _durationLabel(int seconds) {
    final safeSeconds = seconds < 0 ? 0 : seconds;
    if (safeSeconds < 60) return 'less than a minute';
    if (safeSeconds < 3600) return '${safeSeconds ~/ 60} minutes';
    if (safeSeconds < 86400) return '${safeSeconds ~/ 3600} hours';
    return '${safeSeconds ~/ 86400} days';
  }

  static int _compareAttention(
    HomeAttentionItem left,
    HomeAttentionItem right,
  ) {
    final severityOrder = left.status.priority.compareTo(right.status.priority);
    if (severityOrder != 0) return severityOrder;
    final leftTime = left.occurredAt;
    final rightTime = right.occurredAt;
    if (leftTime != null && rightTime != null) {
      final recency = rightTime.compareTo(leftTime);
      if (recency != 0) return recency;
    } else if (leftTime != null) {
      return -1;
    } else if (rightTime != null) {
      return 1;
    }
    return left.id.compareTo(right.id);
  }

  Future<_LoadResult<T>> _capture<T>(Future<T> Function() load) async {
    try {
      return _LoadResult<T>.success(await load());
    } on ApiFailure catch (failure) {
      return _LoadResult<T>.failure(failure);
    } catch (_) {
      return _LoadResult<T>.failure(_unreadableHomeFailure());
    }
  }

  ApiFailure _unreadableHomeFailure() => const ApiFailure(
    kind: ApiFailureKind.unknown,
    message: 'AquaLogic returned Home data that could not be read.',
    retryable: true,
  );
}

class _LoadResult<T> {
  const _LoadResult.success(this.value) : failure = null;
  const _LoadResult.failure(this.failure) : value = null;

  final T? value;
  final ApiFailure? failure;
}

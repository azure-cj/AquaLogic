import 'package:aqualogic/features/alerts/data/alert_api_models.dart';
import 'package:aqualogic/features/alerts/data/mock_alert_repository.dart';
import 'package:aqualogic/features/alerts/models/alert_info.dart';
import 'package:aqualogic/features/sensors/models/sensor_snapshot.dart';
import 'package:aqualogic/shared/formatters/local_timestamps.dart';
import 'package:aqualogic/shared/formatters/sensor_parameter_labels.dart';
import 'package:aqualogic/shared/network/api_client.dart';
import 'package:aqualogic/shared/network/api_failure.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Production alert and monitoring integration. It shares M1's authenticated
/// client, maps FastAPI DTOs into mobile domain objects, and performs no
/// actuator/equipment mutations.
class ApiAlertRepository implements AlertRepository {
  ApiAlertRepository({required this.apiClient});

  static const activeAlertsPath = '/alerts';
  static const alertHistoryPath = '/alerts/history?resolved=true';
  static const tankNamesPath = '/tanks?lifecycle=all';
  static const monitoringPageSize = 25;

  final ApiClient apiClient;
  Future<Map<int, String>>? _tankNamesInFlightOrCached;

  @override
  bool get isLiveData => true;

  @override
  Future<List<AlertInfo>> loadWaterQualityAlerts({
    required SensorSnapshot snapshot,
    required bool history,
  }) async {
    try {
      final response = await apiClient.get(
        history ? alertHistoryPath : activeAlertsPath,
        authenticated: true,
      );
      final body = response.body;
      if (body is! List) {
        throw const FormatException('Expected alert list.');
      }
      final dtos = body.map(AlertReadDto.fromJson).toList(growable: false);
      if (dtos.isEmpty) return const <AlertInfo>[];
      final tankNames = await _loadTankNames();
      final alerts = dtos
          .map((dto) => _mapAlert(dto, tankNames))
          .where((alert) => alert.isActive != history)
          .toList(growable: true);
      if (!history) {
        alerts.sort(_compareActiveAlerts);
      }
      // `/alerts/history` orders by creation time descending. Keep that order
      // as the authoritative history ordering while using the ID as a stable
      // tie-breaker for equal timestamps.
      if (history) alerts.sort(_compareNewestFirst);
      return List.unmodifiable(alerts);
    } on ApiFailure {
      rethrow;
    } on FormatException {
      throw _unreadable('alert');
    }
  }

  @override
  Future<MonitoringIncidentPage> loadMonitoringIncidents({
    required SensorSnapshot snapshot,
    required bool history,
    required int page,
    int pageSize = monitoringPageSize,
  }) async {
    if (page < 1 || pageSize < 1 || pageSize > 100) {
      throw ArgumentError('Monitoring page must be within the backend limits.');
    }
    final state = history ? 'resolved' : 'active';
    try {
      final response = await apiClient.get(
        '/monitoring-incidents?state=$state&page=$page&page_size=$pageSize',
        authenticated: true,
      );
      final dto = MonitoringIncidentPageDto.fromJson(response.body);
      if (dto.items.any((item) => item.state != state)) {
        throw const FormatException('Monitoring state did not match request.');
      }
      return MonitoringIncidentPage(
        items: List.unmodifiable(dto.items.map(_mapMonitoringIncident)),
        page: dto.page,
        pageSize: dto.pageSize,
        total: dto.total,
        totalPages: dto.totalPages,
        hasNext: dto.hasNext,
      );
    } on ApiFailure {
      rethrow;
    } on FormatException {
      throw _unreadable('monitoring incident');
    }
  }

  @override
  Future<AlertInfo?> findWaterQualityAlert({
    required SensorSnapshot snapshot,
    required String alertId,
  }) async {
    final wantedId = int.tryParse(alertId);
    if (wantedId == null || wantedId <= 0) {
      // Non-numeric demo IDs are valid only in MockAlertRepository.
      return null;
    }
    for (final history in const [false, true]) {
      final alerts = await loadWaterQualityAlerts(
        snapshot: snapshot,
        history: history,
      );
      for (final alert in alerts) {
        if (alert.id == wantedId.toString()) return alert;
      }
    }
    return null;
  }

  @override
  Future<MonitoringIncident?> findMonitoringIncident({
    required SensorSnapshot snapshot,
    required String incidentId,
    required bool history,
  }) async {
    final wantedId = int.tryParse(incidentId);
    if (wantedId == null || wantedId <= 0) return null;
    var pageNumber = 1;
    while (true) {
      final page = await loadMonitoringIncidents(
        snapshot: snapshot,
        history: history,
        page: pageNumber,
      );
      for (final incident in page.items) {
        if (incident.id == wantedId.toString()) return incident;
      }
      if (!page.hasNext) return null;
      pageNumber++;
    }
  }

  @override
  Future<AlertInfo> resolveAlert(String alertId) async {
    final id = int.tryParse(alertId);
    if (id == null || id <= 0) throw ApiFailure.fromStatus(404);
    try {
      // The FastAPI route accepts no body. It is naturally idempotent: if the
      // alert is already resolved it returns the existing lifecycle record.
      final response = await apiClient.put(
        '/alerts/$id/resolve',
        authenticated: true,
      );
      final dto = AlertReadDto.fromJson(response.body);
      if (dto.id != id || !dto.isResolved) {
        throw const FormatException('Resolve response did not confirm state.');
      }
      return _mapAlert(dto, await _loadTankNames());
    } on ApiFailure {
      rethrow;
    } on FormatException {
      throw _unreadable('alert resolution');
    }
  }

  Future<Map<int, String>> _loadTankNames() async {
    final pending = _tankNamesInFlightOrCached;
    if (pending != null) {
      try {
        return await pending;
      } catch (_) {
        _tankNamesInFlightOrCached = null;
        return const {};
      }
    }
    final request = _fetchTankNames();
    _tankNamesInFlightOrCached = request;
    try {
      return await request;
    } catch (_) {
      if (identical(_tankNamesInFlightOrCached, request)) {
        _tankNamesInFlightOrCached = null;
      }
      // AlertRead intentionally omits tank display names. A single bounded
      // directory lookup enriches the list; if it fails, IDs remain explicit
      // and no per-alert tank-detail requests are made.
      return const {};
    }
  }

  Future<Map<int, String>> _fetchTankNames() async {
    final response = await apiClient.get(tankNamesPath, authenticated: true);
    if (response.body is! List) {
      throw const FormatException('Expected tank name list.');
    }
    final names = <int, String>{};
    for (final value in response.body as List) {
      final tank = TankAlertNameDto.fromJson(value);
      names[tank.id] = tank.name;
    }
    return Map.unmodifiable(names);
  }

  static AlertInfo _mapAlert(AlertReadDto dto, Map<int, String> tankNames) {
    final severity = switch (dto.severity.toLowerCase()) {
      'warning' => AlertSeverity.warning,
      'critical' => AlertSeverity.critical,
      _ => throw const FormatException('Unknown alert severity.'),
    };
    final resolutionSource = switch (dto.resolutionSource) {
      'operator' => AlertResolutionSource.operator,
      'system' => AlertResolutionSource.system,
      null => null,
      _ => AlertResolutionSource.unknown,
    };
    final lifecycle = !dto.isResolved
        ? AlertLifecycle.active
        : switch (resolutionSource) {
            AlertResolutionSource.operator => AlertLifecycle.handled,
            AlertResolutionSource.system =>
              AlertLifecycle.resolvedAutomatically,
            AlertResolutionSource.unknown || null => AlertLifecycle.resolved,
          };
    return AlertInfo(
      id: dto.id.toString(),
      tankId: dto.tankId.toString(),
      tankName: tankNames[dto.tankId] ?? 'Tank #${dto.tankId}',
      parameter: sensorParameterLabel(dto.parameter),
      severity: severity,
      message: dto.message,
      startedLabel: 'Started ${formatLocalTimestamp(dto.createdAt)}',
      lifecycle: lifecycle,
      readingId: dto.readingId,
      startedAt: dto.createdAt,
      resolvedAt: dto.resolvedAt,
      resolvedByUserId: dto.resolvedByUserId,
      resolutionSource: resolutionSource,
      icon: severity == AlertSeverity.critical
          ? LucideIcons.circleAlert
          : LucideIcons.triangleAlert,
    );
  }

  static MonitoringIncident _mapMonitoringIncident(
    MonitoringIncidentReadDto dto,
  ) {
    if (dto.state != 'active' && dto.state != 'resolved') {
      throw const FormatException('Unknown monitoring incident state.');
    }
    if (dto.tankLifecycle != 'active' && dto.tankLifecycle != 'retired') {
      throw const FormatException('Unknown tank lifecycle.');
    }
    final reason = switch (dto.resolutionReason) {
      'reporting_recovered' => MonitoringResolutionReason.reportingRecovered,
      'monitoring_disabled' => MonitoringResolutionReason.monitoringDisabled,
      'tank_retired' => MonitoringResolutionReason.tankRetired,
      null => null,
      _ => MonitoringResolutionReason.unknown,
    };
    final incident = MonitoringIncident(
      id: dto.id.toString(),
      tankId: dto.tankId.toString(),
      tankName: dto.tankName,
      message: dto.state == 'active'
          ? 'No recent sensor report received.'
          : _messageForReason(reason),
      startedLabel: 'Started ${formatLocalTimestamp(dto.startedAt)}',
      status: dto.state == 'active'
          ? MonitoringIncidentStatus.active
          : MonitoringIncidentStatus.resolved,
      startedAt: dto.startedAt,
      detectedAt: dto.detectedAt,
      resolvedAt: dto.resolvedAt,
      lastReadingReceivedAt: dto.lastReadingReceivedAt,
      lastReportAgeSeconds: dto.lastReportAgeSeconds,
      durationSeconds: dto.durationSeconds,
      resolutionReason: reason,
      recoveredLabel: dto.resolvedAt == null
          ? null
          : '${reason == MonitoringResolutionReason.reportingRecovered ? 'Recovered' : 'Resolved'} ${formatLocalTimestamp(dto.resolvedAt!)}',
    );
    return incident;
  }

  static String _messageForReason(MonitoringResolutionReason? reason) =>
      switch (reason) {
        MonitoringResolutionReason.reportingRecovered =>
          'Reporting recovered and a new reading was received.',
        MonitoringResolutionReason.monitoringDisabled =>
          'Monitoring was disabled for this tank.',
        MonitoringResolutionReason.tankRetired =>
          'This tank was retired; reporting is no longer expected.',
        MonitoringResolutionReason.unknown ||
        null => 'This monitoring incident is resolved.',
      };

  static int _compareActiveAlerts(AlertInfo left, AlertInfo right) {
    final severityOrder = _severityPriority(
      left.severity,
    ).compareTo(_severityPriority(right.severity));
    return severityOrder == 0
        ? _compareNewestFirst(left, right)
        : severityOrder;
  }

  static int _compareNewestFirst(AlertInfo left, AlertInfo right) {
    final leftTime = left.startedAt;
    final rightTime = right.startedAt;
    if (leftTime != null && rightTime != null) {
      final timeOrder = rightTime.compareTo(leftTime);
      if (timeOrder != 0) return timeOrder;
    }
    final leftId = int.tryParse(left.id) ?? 0;
    final rightId = int.tryParse(right.id) ?? 0;
    return rightId.compareTo(leftId);
  }

  static int _severityPriority(AlertSeverity severity) => switch (severity) {
    AlertSeverity.critical => 0,
    AlertSeverity.warning => 1,
  };

  static ApiFailure _unreadable(String label) => ApiFailure(
    kind: ApiFailureKind.unknown,
    message: 'AquaLogic returned $label data that could not be read.',
    retryable: true,
  );
}

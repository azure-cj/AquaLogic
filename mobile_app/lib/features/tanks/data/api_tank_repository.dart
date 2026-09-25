import 'package:aqualogic/features/sensors/models/sensor_snapshot.dart';
import 'package:aqualogic/features/tanks/data/mock_tank_repository.dart';
import 'package:aqualogic/features/tanks/data/tank_api_models.dart';
import 'package:aqualogic/features/tanks/models/tank_info.dart';
import 'package:aqualogic/features/tanks/models/tank_status.dart';
import 'package:aqualogic/shared/models/aqualogic_status.dart';
import 'package:aqualogic/shared/network/api_client.dart';
import 'package:aqualogic/shared/network/api_failure.dart';

/// Read-only M3 integration. Tank identity/status summaries come from `/fleet`;
/// detail uses tank metadata plus the operations snapshot and two independent
/// supporting sources. All requests share M1's authenticated ApiClient.
class ApiTankRepository implements TankRepository {
  ApiTankRepository({required this.apiClient});

  static const fleetPath = '/fleet';
  final ApiClient apiClient;

  @override
  bool get isLiveData => true;

  @override
  Future<List<TankInfo>> loadTanks({required SensorSnapshot snapshot}) async {
    try {
      final response = await apiClient.get(fleetPath, authenticated: true);
      if (response.body is! List) {
        throw const FormatException('Expected fleet list.');
      }
      return (response.body as List)
          .map(FleetTankDto.fromJson)
          .map(_mapFleetTank)
          .toList(growable: false);
    } on ApiFailure {
      rethrow;
    } on FormatException {
      throw _unreadable('fleet');
    }
  }

  @override
  Future<TankInfo> loadTankDetail(
    String tankId, {
    required SensorSnapshot snapshot,
  }) async {
    final id = int.tryParse(tankId);
    if (id == null || id <= 0) throw ApiFailure.fromStatus(404);

    final metadataRequest = _capture(
      'tank details',
      () async => TankRecordDto.fromJson(
        (await apiClient.get('/tanks/$id', authenticated: true)).body,
      ),
    );
    final operationsRequest = _capture(
      'tank operations',
      () async => TankOperationsDto.fromJson(
        (await apiClient.get(
          '/tanks/$id/operations',
          authenticated: true,
        )).body,
      ),
    );
    final monitoringRequest = _capture(
      'monitoring incidents',
      () async => TankMonitoringPageDto.fromJson(
        (await apiClient.get(
          '/tanks/$id/monitoring-incidents?state=active&page=1&page_size=100',
          authenticated: true,
        )).body,
      ),
    );
    final suitabilityRequest = _capture(
      'species suitability',
      () async => TankSuitabilityDto.fromJson(
        (await apiClient.get(
          '/tanks/$id/species-suitability',
          authenticated: true,
        )).body,
      ),
    );

    final results = await Future.wait<Object>([
      metadataRequest,
      operationsRequest,
      monitoringRequest,
      suitabilityRequest,
    ]);
    final metadata = results[0] as _LoadResult<TankRecordDto>;
    final operations = results[1] as _LoadResult<TankOperationsDto>;
    final monitoring = results[2] as _LoadResult<TankMonitoringPageDto>;
    final suitability = results[3] as _LoadResult<TankSuitabilityDto>;

    final tank = metadata.value;
    if (tank == null) throw metadata.failure ?? _unreadable('tank details');
    if (tank.id != id) throw _unreadable('tank details');

    final operationsData = operations.value;
    if (operationsData != null && operationsData.tankId != id) {
      throw _unreadable('tank operations');
    }
    final monitoringData = monitoring.value;
    final suitabilityData = suitability.value;
    if (suitabilityData != null && suitabilityData.tankId != id) {
      // The assignments remain useful; an unrelated advisory payload must not
      // be attached to them.
      return _mapTankDetail(
        tank,
        operationsData,
        monitoringData,
        null,
        operationsAvailable: operationsData != null,
        monitoringAvailable: monitoringData != null,
        suitabilityAvailable: false,
      );
    }

    return _mapTankDetail(
      tank,
      operationsData,
      monitoringData,
      suitabilityData,
      operationsAvailable: operationsData != null,
      monitoringAvailable: monitoringData != null,
      suitabilityAvailable: suitabilityData != null,
    );
  }

  TankInfo _mapFleetTank(FleetTankDto dto) {
    final status = operationalStatusFromCode(dto.status);
    return TankInfo(
      id: dto.id.toString(),
      initial: _initial(dto.name),
      name: dto.name,
      subtitle: dto.location,
      status: status.name,
      typeLabel: '',
      volumeLabel: '',
      lastFedLabel: '',
      description: '',
      locationLabel: dto.location,
      lastReportLabel: _freshnessLabel(dto.reportingAgeSeconds, status),
      lastReportedAt: dto.latestReading?.receivedAt ?? dto.lastReadingAt,
      reportingAgeSeconds: dto.reportingAgeSeconds,
      latestCondition: _fleetCondition(dto),
      monitoringLabel: status == OperationalStatus.offline
          ? 'No recent report'
          : 'Reporting normally',
      readings: const [],
      isLiveData: true,
      assignedSpeciesCount: dto.assignedSpeciesCount,
    );
  }

  TankInfo _mapTankDetail(
    TankRecordDto dto,
    TankOperationsDto? operations,
    TankMonitoringPageDto? monitoring,
    TankSuitabilityDto? suitability, {
    required bool operationsAvailable,
    required bool monitoringAvailable,
    required bool suitabilityAvailable,
  }) {
    final lifecycle = dto.lifecycle == 'retired'
        ? TankLifecycle.retired
        : TankLifecycle.active;
    final operationStatus = operations?.status;
    final status = operationStatus == 'retired'
        ? 'offline'
        : operationStatus ?? 'unknown';
    final operational = operationStatus != null && operationStatus != 'retired'
        ? operationalStatusFromCode(operationStatus)
        : null;
    final reading = operations?.latestReading;
    final reportAge = reading == null || operations == null
        ? null
        : _ageSeconds(operations.evaluatedAt, reading.receivedAt);

    final suitabilityBySpecies = <int, SpeciesSuitability>{
      for (final item
          in suitability?.species ?? const <TankSuitableSpeciesDto>[])
        item.speciesId: _suitability(item.status),
    };
    final species = dto.fishSpecies
        .map(
          (item) => TankSpeciesSummary(
            speciesId: item.id.toString(),
            name: item.commonName,
            suitability:
                suitabilityBySpecies[item.id] ?? SpeciesSuitability.unavailable,
          ),
        )
        .toList(growable: false);

    final issues = <TankIssue>[];
    for (final alert in operations?.activeAlerts ?? const <TankAlertDto>[]) {
      if (alert.tankId != dto.id || alert.isResolved) continue;
      final severity = switch (alert.severity) {
        'warning' => TankIssueSeverity.warning,
        'critical' => TankIssueSeverity.critical,
        _ => throw const FormatException('Unknown alert severity.'),
      };
      issues.add(
        TankIssue(
          id: 'water-alert-${alert.id}',
          category: TankIssueCategory.waterQuality,
          severity: severity,
          title:
              '${severity.name == 'critical' ? 'Critical' : 'Warning'} ${_parameterLabel(alert.parameter)} reading',
          message: alert.message,
          timeLabel:
              'Started ${_relativeTime(_ageSeconds(DateTime.now().toUtc(), alert.createdAt))} ago',
          lifecycle: TankIssueLifecycle.active,
        ),
      );
    }
    for (final incident
        in monitoring?.items ?? const <TankMonitoringIncidentDto>[]) {
      if (incident.tankId != dto.id ||
          incident.state != 'active' ||
          incident.tankLifecycle != 'active') {
        continue;
      }
      final reportAge = incident.lastReportAgeSeconds;
      issues.add(
        TankIssue(
          id: 'monitoring-incident-${incident.id}',
          category: TankIssueCategory.monitoring,
          severity: TankIssueSeverity.info,
          title: 'Monitoring incident active',
          message: reportAge == null
              ? 'The backend has an active monitoring incident for this tank.'
              : 'The last sensor report was received ${_relativeTime(reportAge)} ago.',
          timeLabel:
              'Detected ${_relativeTime(_ageSeconds(DateTime.now().toUtc(), incident.detectedAt))} ago',
          lifecycle: TankIssueLifecycle.active,
        ),
      );
    }

    final typeLabel = dto.habitatLabel?.trim() ?? '';
    final volumeLabel = dto.volumeLiters == null ? '' : '${dto.volumeLiters} L';
    final subtitleParts = [
      if (typeLabel.isNotEmpty) typeLabel,
      if (volumeLabel.isNotEmpty) volumeLabel,
    ];
    final subtitle = subtitleParts.isEmpty
        ? dto.location
        : subtitleParts.join(' · ');

    return TankInfo(
      id: dto.id.toString(),
      initial: _initial(dto.name),
      name: dto.name,
      subtitle: subtitle,
      status: status,
      typeLabel: typeLabel,
      volumeLabel: volumeLabel,
      lastFedLabel: '',
      description: dto.description?.trim() ?? '',
      locationLabel: dto.location,
      lastReportLabel: lifecycle == TankLifecycle.retired
          ? 'Monitoring not expected'
          : operationsAvailable
          ? _freshnessLabel(reportAge, operational)
          : 'Status unavailable',
      lastReportedAt: reading?.receivedAt,
      reportingAgeSeconds: reportAge,
      latestCondition: operationsAvailable
          ? _detailCondition(operational)
          : 'Current operating status is unavailable.',
      monitoringLabel: lifecycle == TankLifecycle.retired
          ? 'Monitoring not expected'
          : operational == OperationalStatus.offline
          ? 'No recent report'
          : operationsAvailable
          ? 'Reporting normally'
          : 'Status unavailable',
      lifecycle: lifecycle,
      readings: operationsAvailable
          ? _readings(reading, operations!.parameterStatuses, reportAge)
          : const [],
      issues: issues,
      species: species,
      equipmentCount: 0,
      recentActivity: const [],
      isLiveData: true,
      operationsAvailable: operationsAvailable,
      monitoringAvailable: monitoringAvailable,
      suitabilityAvailable: suitabilityAvailable,
      assignedSpeciesCount: dto.fishSpecies.length,
    );
  }

  static List<TankReading> _readings(
    SensorReadingDto? reading,
    Map<String, String> statuses,
    int? reportAge,
  ) {
    return [
      for (final parameter in SensorParameter.values)
        _mapReading(parameter, reading, statuses, reportAge),
    ];
  }

  static TankReading _mapReading(
    SensorParameter parameter,
    SensorReadingDto? reading,
    Map<String, String> statuses,
    int? reportAge,
  ) {
    final key = parameter.name;
    final number = reading?.valueFor(key);
    final backendStatus = statuses[key] ?? 'unavailable';
    final condition = switch (backendStatus) {
      'normal' => ReadingCondition.normal,
      'warning' => ReadingCondition.warning,
      'critical' => ReadingCondition.critical,
      'offline' => ReadingCondition.stale,
      'unavailable' => ReadingCondition.unavailable,
      _ => throw const FormatException('Unknown sensor parameter status.'),
    };
    final stale = condition == ReadingCondition.stale;
    final receivedAt = reading?.receivedAt;
    final age =
        reportAge ??
        (receivedAt == null
            ? null
            : _ageSeconds(DateTime.now().toUtc(), receivedAt));
    final timestampLabel = reading == null
        ? 'No reading received'
        : reading.isMock
        ? 'Demo reading · received ${_relativeTime(age)} ago'
        : stale
        ? 'Last known · received ${_relativeTime(age)} ago'
        : 'Received ${_relativeTime(age)} ago';
    return TankReading(
      parameter: parameter,
      value: number == null ? '—' : _formatValue(parameter, number),
      unit: switch (parameter) {
        SensorParameter.temperature => '°C',
        SensorParameter.ph => 'pH',
        SensorParameter.turbidity => 'NTU',
        SensorParameter.tds => 'ppm',
      },
      condition: number == null ? ReadingCondition.unavailable : condition,
      timestampLabel: timestampLabel,
      observedAt: reading?.timestamp,
      receivedAt: receivedAt,
      isMock: reading?.isMock ?? false,
    );
  }

  static String _formatValue(SensorParameter parameter, double value) {
    final digits = switch (parameter) {
      SensorParameter.temperature || SensorParameter.ph => 1,
      SensorParameter.turbidity ||
      SensorParameter.tds => value == value.roundToDouble() ? 0 : 1,
    };
    return value.toStringAsFixed(digits);
  }

  static String _fleetCondition(FleetTankDto tank) {
    final status = operationalStatusFromCode(tank.status);
    return switch (status) {
      OperationalStatus.normal => 'Backend reports readings within range.',
      OperationalStatus.warning =>
        tank.activeWarningCount > 0
            ? '${tank.activeWarningCount} active warning alerts.'
            : 'Backend status needs review.',
      OperationalStatus.critical =>
        tank.activeCriticalCount > 0
            ? '${tank.activeCriticalCount} active critical alerts.'
            : 'Backend status needs review.',
      OperationalStatus.offline => 'No recent sensor report.',
    };
  }

  static String _detailCondition(OperationalStatus? status) => switch (status) {
    OperationalStatus.normal =>
      'Backend reports readings within configured ranges.',
    OperationalStatus.warning =>
      'Backend reports water readings that need attention.',
    OperationalStatus.critical =>
      'Backend reports critical water-quality status.',
    OperationalStatus.offline => 'No recent sensor report is available.',
    null => 'Current operating status is unavailable.',
  };

  static String _freshnessLabel(int? age, OperationalStatus? status) {
    if (status == OperationalStatus.offline || age == null) {
      return 'No recent report';
    }
    return 'Updated ${_relativeTime(age)} ago';
  }

  static String _relativeTime(int? seconds) {
    if (seconds == null || seconds < 60) {
      return 'just now';
    }
    if (seconds < 3600) {
      return '${seconds ~/ 60} minute${seconds ~/ 60 == 1 ? '' : 's'}';
    }
    if (seconds < 86400) {
      return '${seconds ~/ 3600} hour${seconds ~/ 3600 == 1 ? '' : 's'}';
    }
    return '${seconds ~/ 86400} day${seconds ~/ 86400 == 1 ? '' : 's'}';
  }

  static int _ageSeconds(DateTime now, DateTime then) {
    final seconds = now.difference(then).inSeconds;
    return seconds < 0 ? 0 : seconds;
  }

  static SpeciesSuitability _suitability(String value) => switch (value) {
    'suitable' => SpeciesSuitability.suitable,
    'attention' => SpeciesSuitability.attention,
    'unavailable' => SpeciesSuitability.unavailable,
    _ => throw const FormatException('Unknown suitability state.'),
  };

  static String _parameterLabel(String value) => switch (value.toLowerCase()) {
    'temperature' => 'Temperature',
    'ph' => 'pH',
    'turbidity' => 'Turbidity',
    'tds' => 'TDS',
    _ => value.replaceAll('_', ' '),
  };

  static String _initial(String name) =>
      name.trim().isEmpty ? 'T' : name.trim().substring(0, 1).toUpperCase();

  Future<_LoadResult<T>> _capture<T>(
    String label,
    Future<T> Function() load,
  ) async {
    try {
      return _LoadResult<T>.success(await load());
    } on ApiFailure catch (failure) {
      return _LoadResult<T>.failure(failure);
    } on FormatException {
      return _LoadResult<T>.failure(_unreadable(label));
    }
  }

  ApiFailure _unreadable(String label) => ApiFailure(
    kind: ApiFailureKind.unknown,
    message: 'AquaLogic returned $label data that could not be read.',
    retryable: true,
  );
}

class _LoadResult<T> {
  const _LoadResult.success(this.value) : failure = null;
  const _LoadResult.failure(this.failure) : value = null;

  final T? value;
  final ApiFailure? failure;
}

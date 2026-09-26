import 'package:aqualogic/features/alerts/data/alert_mutation_service.dart';
import 'package:aqualogic/features/alerts/data/mock_alert_repository.dart';
import 'package:aqualogic/features/alerts/models/alert_info.dart';
import 'package:aqualogic/features/sensors/data/mock_sensor_feed.dart';
import 'package:aqualogic/features/sensors/models/sensor_snapshot.dart';
import 'package:aqualogic/shared/network/api_failure.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'confirmed resolve returns the server lifecycle without reconciliation',
    () async {
      final repository = _FakeAlertRepository(
        resolveResult: _activeAlert.copyWith(
          lifecycle: AlertLifecycle.handled,
          resolvedAt: DateTime.utc(2026, 9, 25, 8),
          resolutionSource: AlertResolutionSource.operator,
        ),
      );

      final result = await markAlertHandled(
        repository: repository,
        snapshot: MockSensorFeed.snapshot(0),
        alert: _activeAlert,
      );

      expect(result.isResolved, isTrue);
      expect(result.alert?.statusLabel, 'Handled');
      expect(result.reconciled, isFalse);
      expect(repository.resolveCalls, 1);
      expect(repository.findCalls, 0);
    },
  );

  test(
    'ambiguous timeout reconciles an automatic backend resolution',
    () async {
      final repository = _FakeAlertRepository(
        resolveError: ApiFailure.timeout(),
        foundAlert: _activeAlert.copyWith(
          lifecycle: AlertLifecycle.resolvedAutomatically,
          resolvedAt: DateTime.utc(2026, 9, 25, 8),
          resolutionSource: AlertResolutionSource.system,
        ),
      );

      final result = await markAlertHandled(
        repository: repository,
        snapshot: MockSensorFeed.snapshot(0),
        alert: _activeAlert,
      );

      expect(result.isResolved, isTrue);
      expect(result.alert?.statusLabel, 'Resolved automatically');
      expect(result.failure, isNull);
      expect(result.reconciled, isTrue);
      expect(
        repository.resolveCalls,
        1,
        reason: 'The mutation is not replayed.',
      );
      expect(repository.findCalls, 1);
    },
  );

  test(
    'timeout with still-active alert remains unhandled and is not replayed',
    () async {
      final repository = _FakeAlertRepository(
        resolveError: ApiFailure.timeout(),
        foundAlert: _activeAlert,
      );

      final result = await markAlertHandled(
        repository: repository,
        snapshot: MockSensorFeed.snapshot(0),
        alert: _activeAlert,
      );

      expect(result.isResolved, isFalse);
      expect(result.alert?.isActive, isTrue);
      expect(result.failure?.kind, ApiFailureKind.timeout);
      expect(repository.resolveCalls, 1);
      expect(repository.findCalls, 1);
    },
  );

  test('403 stays a permission error and skips reconciliation', () async {
    final repository = _FakeAlertRepository(
      resolveError: ApiFailure.fromStatus(403),
    );

    final result = await markAlertHandled(
      repository: repository,
      snapshot: MockSensorFeed.snapshot(0),
      alert: _activeAlert,
    );

    expect(result.isResolved, isFalse);
    expect(result.failure?.kind, ApiFailureKind.forbidden);
    expect(repository.resolveCalls, 1);
    expect(repository.findCalls, 0);
  });

  for (final entry in const {
    400: ApiFailureKind.business,
    401: ApiFailureKind.unauthenticated,
    403: ApiFailureKind.forbidden,
    404: ApiFailureKind.notFound,
    409: ApiFailureKind.conflict,
    422: ApiFailureKind.validation,
    429: ApiFailureKind.rateLimited,
  }.entries) {
    test('${entry.key} does not falsely mark an alert handled', () async {
      final repository = _FakeAlertRepository(
        resolveError: ApiFailure.fromStatus(entry.key),
      );

      final result = await markAlertHandled(
        repository: repository,
        snapshot: MockSensorFeed.snapshot(0),
        alert: _activeAlert,
      );

      expect(result.isResolved, isFalse);
      expect(result.alert, isNull);
      expect(result.failure?.kind, entry.value);
      expect(repository.resolveCalls, 1);
      expect(repository.findCalls, 0);
    });
  }

  test(
    'network failure reconciles current state without replaying the PUT',
    () async {
      final repository = _FakeAlertRepository(
        resolveError: ApiFailure.networkUnavailable(),
        foundAlert: _activeAlert,
      );

      final result = await markAlertHandled(
        repository: repository,
        snapshot: MockSensorFeed.snapshot(0),
        alert: _activeAlert,
      );

      expect(result.isResolved, isFalse);
      expect(result.failure?.kind, ApiFailureKind.networkUnavailable);
      expect(result.reconciled, isTrue);
      expect(repository.resolveCalls, 1);
      expect(repository.findCalls, 1);
    },
  );

  test(
    'server failure reconciles a committed resolution without replaying the PUT',
    () async {
      final repository = _FakeAlertRepository(
        resolveError: ApiFailure.fromStatus(500),
        foundAlert: _activeAlert.copyWith(
          lifecycle: AlertLifecycle.handled,
          resolvedAt: DateTime.utc(2026, 9, 25, 8),
          resolutionSource: AlertResolutionSource.operator,
        ),
      );

      final result = await markAlertHandled(
        repository: repository,
        snapshot: MockSensorFeed.snapshot(0),
        alert: _activeAlert,
      );

      expect(result.isResolved, isTrue);
      expect(result.alert?.statusLabel, 'Handled');
      expect(result.failure, isNull);
      expect(result.reconciled, isTrue);
      expect(repository.resolveCalls, 1);
      expect(repository.findCalls, 1);
    },
  );
}

const _activeAlert = AlertInfo(
  id: '52',
  tankId: '8',
  tankName: 'Nursery',
  parameter: 'pH',
  severity: AlertSeverity.warning,
  message: 'pH is outside the configured range.',
  startedLabel: 'Started today',
  lifecycle: AlertLifecycle.active,
);

class _FakeAlertRepository implements AlertRepository {
  _FakeAlertRepository({
    this.resolveResult,
    this.resolveError,
    this.foundAlert,
  });

  final AlertInfo? resolveResult;
  final Object? resolveError;
  final AlertInfo? foundAlert;
  var resolveCalls = 0;
  var findCalls = 0;

  @override
  bool get isLiveData => false;

  @override
  Future<List<AlertInfo>> loadWaterQualityAlerts({
    required SensorSnapshot snapshot,
    required bool history,
  }) async => const [];

  @override
  Future<MonitoringIncidentPage> loadMonitoringIncidents({
    required SensorSnapshot snapshot,
    required bool history,
    required int page,
    int pageSize = 25,
  }) async => MonitoringIncidentPage(
    items: const [],
    page: page,
    pageSize: pageSize,
    total: 0,
    totalPages: 0,
    hasNext: false,
  );

  @override
  Future<AlertInfo?> findWaterQualityAlert({
    required SensorSnapshot snapshot,
    required String alertId,
  }) async {
    findCalls++;
    return foundAlert;
  }

  @override
  Future<MonitoringIncident?> findMonitoringIncident({
    required SensorSnapshot snapshot,
    required String incidentId,
    required bool history,
  }) async => null;

  @override
  Future<AlertInfo> resolveAlert(String alertId) async {
    resolveCalls++;
    final error = resolveError;
    if (error != null) throw error;
    return resolveResult ?? _activeAlert;
  }
}

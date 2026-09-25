import 'package:aqualogic/features/demo/demo_data.dart';
import 'package:aqualogic/features/sensors/models/sensor_snapshot.dart';
import 'package:aqualogic/features/tanks/models/tank_info.dart';
import 'package:aqualogic/shared/models/aqualogic_status.dart';
import 'package:aqualogic/shared/network/api_failure.dart';

abstract class TankRepository {
  bool get isLiveData;

  Future<List<TankInfo>> loadTanks({required SensorSnapshot snapshot});

  Future<TankInfo> loadTankDetail(
    String tankId, {
    required SensorSnapshot snapshot,
  });
}

/// Local tank directory composed from backend-compatible presentation fields.
/// A future API repository can return the same TankInfo model without changing
/// the directory or detail widgets.
class MockTankRepository implements TankRepository {
  const MockTankRepository({this.offlineTankIds = const <String>{}});

  /// Fixture hook for tests and demonstrations of reporting outages.
  final Set<String> offlineTankIds;

  @override
  bool get isLiveData => false;

  @override
  Future<List<TankInfo>> loadTanks({required SensorSnapshot snapshot}) async =>
      list(snapshot: snapshot);

  @override
  Future<TankInfo> loadTankDetail(
    String tankId, {
    required SensorSnapshot snapshot,
  }) async {
    final tank = findById(tankId, snapshot: snapshot);
    if (tank == null) throw ApiFailure.fromStatus(404);
    return tank;
  }

  List<TankInfo> list({required SensorSnapshot snapshot}) {
    return DemoData.tanks
        .map(
          (tank) => _withMonitoringState(
            tank,
            isOffline:
                !snapshot.isOnline || offlineTankIds.contains(tank.tankId),
            reportedAt: snapshot.updatedAt,
          ),
        )
        .toList(growable: false);
  }

  TankInfo? findById(String tankId, {required SensorSnapshot snapshot}) {
    for (final tank in list(snapshot: snapshot)) {
      if (tank.tankId == tankId) return tank;
    }
    return null;
  }

  TankInfo _withMonitoringState(
    TankInfo tank, {
    required bool isOffline,
    required DateTime reportedAt,
  }) {
    if (tank.isRetired) return tank;
    if (!isOffline) {
      return tank.copyWith(lastReportedAt: reportedAt, reportingAgeSeconds: 0);
    }

    final unavailableReadings = tank.readings
        .map(
          (reading) => TankReading(
            parameter: reading.parameter,
            value: '—',
            unit: reading.unit,
            condition: ReadingCondition.unavailable,
            timestampLabel: 'No recent report',
          ),
        )
        .toList(growable: false);
    final unavailableSpecies = tank.species
        .map(
          (species) => TankSpeciesSummary(
            speciesId: species.speciesId,
            name: species.name,
            suitability: SpeciesSuitability.unavailable,
            count: species.count,
          ),
        )
        .toList(growable: false);
    final issues = <TankIssue>[
      TankIssue(
        id: '${tank.tankId}-monitoring',
        category: TankIssueCategory.monitoring,
        severity: TankIssueSeverity.info,
        title: 'No readings received recently',
        message: 'Monitoring cannot confirm the current water condition.',
        timeLabel: 'Active now',
        lifecycle: TankIssueLifecycle.active,
      ),
    ];

    return tank.copyWith(
      status: 'OFFLINE',
      lastReportLabel: 'No recent report',
      latestCondition: 'No current reading is available.',
      monitoringLabel: 'No recent report',
      readings: unavailableReadings,
      species: unavailableSpecies,
      issues: issues,
    );
  }
}

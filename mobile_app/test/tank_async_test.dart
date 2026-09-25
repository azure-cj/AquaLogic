import 'dart:async';

import 'package:aqualogic/app/navigation/aqualogic_shell.dart';
import 'package:aqualogic/features/auth/models/auth_user.dart';
import 'package:aqualogic/features/auth/models/user_role.dart';
import 'package:aqualogic/features/home/data/home_repository.dart';
import 'package:aqualogic/features/home/models/home_dashboard_data.dart';
import 'package:aqualogic/features/sensors/data/mock_sensor_feed.dart';
import 'package:aqualogic/features/sensors/models/sensor_snapshot.dart';
import 'package:aqualogic/features/tanks/data/mock_tank_repository.dart';
import 'package:aqualogic/features/tanks/models/tank_info.dart';
import 'package:aqualogic/features/tanks/screens/tank_detail_screen.dart';
import 'package:aqualogic/features/tanks/screens/tanks_screen.dart';
import 'package:aqualogic/shared/models/aqualogic_status.dart';
import 'package:aqualogic/shared/network/api_failure.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Tanks shows loading first, then real repository data', (
    tester,
  ) async {
    final result = Completer<List<TankInfo>>();
    final repository = _TankTestRepository(
      fetchTanks: () => result.future,
      loadDetail: (_) async => _liveTank(id: '42', name: 'Reef 42'),
    );

    await tester.pumpWidget(_tanksApp(repository));
    await tester.pump();
    expect(find.byKey(const ValueKey('tanks-loading-content')), findsOneWidget);
    expect(find.text('Display Reef A'), findsNothing);

    result.complete([_liveTank(id: '42', name: 'Reef 42')]);
    await tester.pumpAndSettle();
    expect(find.text('Reef 42'), findsOneWidget);
    expect(find.byKey(const ValueKey('tanks-loading-content')), findsNothing);
  });

  testWidgets('zero active tanks shows an honest empty directory', (
    tester,
  ) async {
    final repository = _TankTestRepository(
      fetchTanks: () async => const [],
      loadDetail: (_) async => _liveTank(id: '42', name: 'Reef 42'),
    );
    await tester.pumpWidget(_tanksApp(repository));
    await tester.pumpAndSettle();
    expect(find.text('No active tanks'), findsOneWidget);
    expect(
      find.text('AquaLogic currently has no active tanks for this account.'),
      findsOneWidget,
    );
    expect(find.text('Display Reef A'), findsNothing);
  });

  testWidgets('directory filters and search use backend tank identity fields', (
    tester,
  ) async {
    final repository = _TankTestRepository(
      fetchTanks: () async => [
        _liveTank(id: '1', name: 'Reef One', location: 'North room'),
        _liveTank(
          id: '2',
          name: 'Quarantine Two',
          status: 'warning',
          location: 'Treatment room',
        ),
        _liveTank(
          id: '3',
          name: 'Nursery Three',
          status: 'critical',
          location: 'Propagation room',
        ),
        _liveTank(
          id: '4',
          name: 'Reserve Four',
          status: 'offline',
          location: 'North room',
        ),
      ],
      loadDetail: (_) async => _liveTank(id: '42', name: 'Reef 42'),
    );
    await tester.pumpWidget(_tanksApp(repository));
    await tester.pumpAndSettle();

    expect(find.text('4 tanks · 2 need attention'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tank-filter-attention')));
    await tester.pumpAndSettle();
    expect(find.text('Quarantine Two'), findsOneWidget);
    expect(find.text('Nursery Three'), findsOneWidget);
    expect(find.text('Reef One'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('tank-filter-offline')));
    await tester.pumpAndSettle();
    expect(find.text('Reserve Four'), findsOneWidget);
    expect(find.text('Quarantine Two'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('tank-filter-all')));
    await tester.enterText(find.byType(TextField), 'treatment');
    await tester.pumpAndSettle();
    expect(find.text('Quarantine Two'), findsOneWidget);
    expect(find.text('Reef One'), findsNothing);
  });

  testWidgets(
    'Tanks connection failure retries without marking tanks offline',
    (tester) async {
      var loads = 0;
      final repository = _TankTestRepository(
        fetchTanks: () async {
          loads++;
          if (loads == 1) throw ApiFailure.networkUnavailable();
          return [_liveTank(id: '42', name: 'Reef 42')];
        },
        loadDetail: (_) async => _liveTank(id: '42', name: 'Reef 42'),
      );
      await tester.pumpWidget(_tanksApp(repository));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('tanks-load-error')), findsOneWidget);
      expect(find.text("Couldn't load Tanks from AquaLogic"), findsOneWidget);
      expect(find.text('1 tank offline'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('tanks-load-retry')));
      await tester.pumpAndSettle();
      expect(loads, 2);
      expect(find.text('Reef 42'), findsOneWidget);
      expect(find.byKey(const ValueKey('tanks-load-error')), findsNothing);
    },
  );

  testWidgets(
    'pull refresh retains search and shows stale list after failure',
    (tester) async {
      var loads = 0;
      final repository = _TankTestRepository(
        fetchTanks: () async {
          loads++;
          if (loads == 1) {
            return [
              _liveTank(id: '1', name: 'Reef One'),
              _liveTank(id: '2', name: 'Quarantine Two'),
            ];
          }
          throw ApiFailure.networkUnavailable();
        },
        loadDetail: (_) async => _liveTank(id: '42', name: 'Reef 42'),
      );
      await tester.pumpWidget(_tanksApp(repository));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Quarantine');
      await tester.pumpAndSettle();

      await tester.dragFrom(const Offset(170, 120), const Offset(0, 420));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(loads, 2);
      expect(find.byKey(const ValueKey('tanks-stale-retry')), findsOneWidget);
      expect(find.text('Quarantine Two'), findsOneWidget);
      expect(find.text('Reef One'), findsNothing);
    },
  );

  testWidgets(
    'detail waits for data, renders real sections, and hides mock-only content',
    (tester) async {
      final result = Completer<TankInfo>();
      final repository = _TankTestRepository(
        fetchTanks: () async => const [],
        loadDetail: (_) => result.future,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: TankDetailPage(
            tankId: '42',
            repository: repository,
            snapshot: MockSensorFeed.snapshot(0),
            user: _owner,
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Loading tank details from AquaLogic'), findsOneWidget);
      expect(find.text('Display Reef A'), findsNothing);

      result.complete(_liveTank(id: '42', name: 'Reef 42', status: 'warning'));
      await tester.pumpAndSettle();
      expect(repository.requestedDetailIds, ['42']);
      expect(find.text('Reef 42'), findsOneWidget);
      expect(find.text('North room'), findsOneWidget);
      expect(find.text('320 L'), findsOneWidget);
      expect(find.text('Last fed'), findsNothing);
      expect(
        find.byKey(const ValueKey('sensor-overview-panel')),
        findsOneWidget,
      );
      expect(find.text('Temperature'), findsOneWidget);
      expect(find.text('26.4'), findsOneWidget);
      expect(find.text('NTU'), findsOneWidget);
      expect(find.text('ppm'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Warning pH reading'),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Water quality'), findsOneWidget);
      expect(find.text('Warning pH reading'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Clownfish'),
        280,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Clownfish'), findsOneWidget);
      expect(find.text('Suitable'), findsWidgets);
      expect(find.text('No recent activity'), findsNothing);
      expect(find.text('Recent activity'), findsNothing);
      expect(find.byKey(const ValueKey('tank-equipment-entry')), findsNothing);
    },
  );

  testWidgets('detail with no reading shows unavailable values, not zero', (
    tester,
  ) async {
    final repository = _TankTestRepository(
      fetchTanks: () async => const [],
      loadDetail: (_) async =>
          _liveTank(id: '42', name: 'Reef 42', readings: const []),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: TankDetailPage(
          tankId: '42',
          repository: repository,
          snapshot: MockSensorFeed.snapshot(0),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No sensor readings are available.'), findsOneWidget);
    expect(find.text('0.0'), findsNothing);
    expect(find.text('Offline'), findsNothing);
  });

  testWidgets(
    'partial readings preserve a real zero and mark nulls unavailable',
    (tester) async {
      final repository = _TankTestRepository(
        fetchTanks: () async => const [],
        loadDetail: (_) async => _liveTank(
          id: '42',
          name: 'Reef 42',
          readings: [
            _tankReading(SensorParameter.temperature, '0.0', '°C'),
            _tankReading(
              SensorParameter.ph,
              '—',
              'pH',
              condition: ReadingCondition.unavailable,
            ),
            _tankReading(
              SensorParameter.turbidity,
              '—',
              'NTU',
              condition: ReadingCondition.unavailable,
            ),
            _tankReading(
              SensorParameter.tds,
              '—',
              'ppm',
              condition: ReadingCondition.unavailable,
            ),
          ],
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: TankDetailPage(
            tankId: '42',
            repository: repository,
            snapshot: MockSensorFeed.snapshot(0),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('0.0'), findsOneWidget);
      expect(find.text('—'), findsAtLeastNWidgets(1));
      expect(find.text('Unavailable'), findsAtLeastNWidgets(1));
    },
  );

  testWidgets('offline monitoring state remains separate from water alerts', (
    tester,
  ) async {
    final repository = _TankTestRepository(
      fetchTanks: () async => const [],
      loadDetail: (_) async => _liveTank(
        id: '42',
        name: 'Reef 42',
        status: 'offline',
        readings: [
          _tankReading(
            SensorParameter.temperature,
            '26.4',
            '°C',
            condition: ReadingCondition.stale,
          ),
        ],
        issues: const [
          TankIssue(
            id: 'monitoring-11',
            category: TankIssueCategory.monitoring,
            severity: TankIssueSeverity.info,
            title: 'Monitoring incident active',
            message: 'The backend reports a current monitoring outage.',
            timeLabel: 'Detected just now',
            lifecycle: TankIssueLifecycle.active,
          ),
        ],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: TankDetailPage(
          tankId: '42',
          repository: repository,
          snapshot: MockSensorFeed.snapshot(0),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Offline'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Monitoring incident active'),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Monitoring'), findsOneWidget);
    expect(find.text('Monitoring incident active'), findsOneWidget);
    expect(find.text('Water quality'), findsNothing);
  });

  testWidgets('empty assigned-species result is shown truthfully', (
    tester,
  ) async {
    final repository = _TankTestRepository(
      fetchTanks: () async => const [],
      loadDetail: (_) async => _liveTank(
        id: '42',
        name: 'Reef 42',
        species: const [],
        assignedSpeciesCount: 0,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: TankDetailPage(
          tankId: '42',
          repository: repository,
          snapshot: MockSensorFeed.snapshot(0),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('No species assigned to this tank'),
      280,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('No species assigned to this tank'), findsOneWidget);
    expect(find.text('Clownfish'), findsNothing);
  });

  testWidgets('secondary-source errors retain the real tank and readings', (
    tester,
  ) async {
    final repository = _TankTestRepository(
      fetchTanks: () async => const [],
      loadDetail: (_) async => _liveTank(
        id: '42',
        name: 'Reef 42',
        monitoringAvailable: false,
        suitabilityAvailable: false,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: TankDetailPage(
          tankId: '42',
          repository: repository,
          snapshot: MockSensorFeed.snapshot(0),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Reef 42'), findsOneWidget);
    expect(find.text('26.4'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Monitoring incident details unavailable'),
      280,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.text('Monitoring incident details unavailable'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('Suitability unavailable'),
      280,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Suitability unavailable'), findsOneWidget);
    expect(find.text('Clownfish'), findsOneWidget);
  });

  testWidgets('operations failure is labelled unavailable, not tank offline', (
    tester,
  ) async {
    final repository = _TankTestRepository(
      fetchTanks: () async => const [],
      loadDetail: (_) async => _liveTank(
        id: '42',
        name: 'Reef 42',
        status: 'unknown',
        operationsAvailable: false,
        monitoringAvailable: false,
        suitabilityAvailable: false,
        readings: const [],
        issues: const [],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: TankDetailPage(
          tankId: '42',
          repository: repository,
          snapshot: MockSensorFeed.snapshot(0),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Status unavailable'), findsWidgets);
    expect(find.text('Current readings unavailable'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Monitoring status unavailable'),
      280,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Monitoring status unavailable'), findsOneWidget);
    expect(find.text('Offline'), findsNothing);
    expect(find.text('No active issues'), findsNothing);
  });

  testWidgets('tank not found is a detail error rather than no-reading state', (
    tester,
  ) async {
    final repository = _TankTestRepository(
      fetchTanks: () async => const [],
      loadDetail: (_) async => throw ApiFailure.fromStatus(404),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: TankDetailPage(
          tankId: '42',
          repository: repository,
          snapshot: MockSensorFeed.snapshot(0),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Tank not found or no longer accessible'), findsOneWidget);
    expect(find.text('No sensor readings are available.'), findsNothing);
    expect(find.text('Offline'), findsNothing);
  });

  testWidgets('Home card and Tanks directory request detail with the same ID', (
    tester,
  ) async {
    final tank = _liveTank(id: '42', name: 'Live Reef');
    final repository = _TankTestRepository(
      fetchTanks: () async => [tank],
      loadDetail: (id) async => _liveTank(id: id, name: 'Backend Tank $id'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AquaLogicShell(
          user: _owner,
          homeRepository: _LiveHomeRepository(),
          tankRepository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Live Reef').first);
    await tester.pumpAndSettle();
    expect(repository.requestedDetailIds, ['42']);
    expect(find.text('Backend Tank 42'), findsOneWidget);
    await tester.tap(find.byTooltip('Back to Tanks'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('soft-floating-dock-destination-1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tank-card-42')));
    await tester.pumpAndSettle();
    expect(repository.requestedDetailIds, ['42', '42']);
    expect(find.text('Backend Tank 42'), findsOneWidget);
  });
}

Widget _tanksApp(_TankTestRepository repository) => MaterialApp(
  home: Scaffold(
    body: TanksScreen(
      snapshot: MockSensorFeed.snapshot(0),
      repository: repository,
    ),
  ),
);

TankInfo _liveTank({
  required String id,
  required String name,
  String status = 'normal',
  String location = 'North room',
  List<TankReading>? readings,
  List<TankIssue>? issues,
  List<TankSpeciesSummary>? species,
  int assignedSpeciesCount = 1,
  bool operationsAvailable = true,
  bool monitoringAvailable = true,
  bool suitabilityAvailable = true,
}) => TankInfo(
  id: id,
  initial: name.substring(0, 1),
  name: name,
  subtitle: 'Marine reef · 320 L',
  status: status,
  typeLabel: 'Marine reef',
  volumeLabel: '320 L',
  lastFedLabel: '',
  description: 'Backend description',
  locationLabel: location,
  lastReportLabel: status == 'offline'
      ? 'No recent report'
      : 'Updated just now',
  latestCondition: status == 'normal'
      ? 'Backend reports readings within configured ranges.'
      : 'Backend status requires review.',
  lifecycle: TankLifecycle.active,
  readings:
      readings ??
      [
        _tankReading(SensorParameter.temperature, '26.4', '°C'),
        _tankReading(SensorParameter.ph, '8.1', 'pH'),
        _tankReading(SensorParameter.turbidity, '12', 'NTU'),
        _tankReading(SensorParameter.tds, '230', 'ppm'),
      ],
  issues:
      issues ??
      [
        const TankIssue(
          id: 'alert-10',
          category: TankIssueCategory.waterQuality,
          severity: TankIssueSeverity.warning,
          title: 'Warning pH reading',
          message: 'Backend alert message.',
          timeLabel: 'Started just now',
          lifecycle: TankIssueLifecycle.active,
        ),
        const TankIssue(
          id: 'monitoring-10',
          category: TankIssueCategory.monitoring,
          severity: TankIssueSeverity.info,
          title: 'Monitoring incident active',
          message:
              'The backend has an active monitoring incident for this tank.',
          timeLabel: 'Detected just now',
          lifecycle: TankIssueLifecycle.active,
        ),
      ],
  species:
      species ??
      const [
        TankSpeciesSummary(
          speciesId: '77',
          name: 'Clownfish',
          suitability: SpeciesSuitability.suitable,
        ),
      ],
  equipmentCount: 5,
  recentActivity: const [
    TankActivity(
      id: 'mock-event',
      title: 'Mock feeding event',
      detail: 'This must not appear in live detail.',
      timeLabel: 'Just now',
    ),
  ],
  isLiveData: true,
  operationsAvailable: operationsAvailable,
  monitoringAvailable: monitoringAvailable,
  suitabilityAvailable: suitabilityAvailable,
  assignedSpeciesCount: assignedSpeciesCount,
);

TankReading _tankReading(
  SensorParameter parameter,
  String value,
  String unit, {
  ReadingCondition condition = ReadingCondition.normal,
}) => TankReading(
  parameter: parameter,
  value: value,
  unit: unit,
  condition: condition,
  timestampLabel: 'Received just now',
  receivedAt: DateTime.utc(2026, 9, 25),
  observedAt: DateTime.utc(2026, 9, 25),
);

const _owner = AuthUser(
  id: 'owner-1',
  name: 'Owner',
  email: 'owner@example.test',
  role: UserRole.admin,
);

class _TankTestRepository implements TankRepository {
  _TankTestRepository({required this.fetchTanks, required this.loadDetail});

  final Future<List<TankInfo>> Function() fetchTanks;
  final Future<TankInfo> Function(String id) loadDetail;
  final requestedDetailIds = <String>[];
  var listCount = 0;

  @override
  bool get isLiveData => true;

  @override
  Future<List<TankInfo>> loadTanks({required SensorSnapshot snapshot}) {
    listCount++;
    return fetchTanks();
  }

  @override
  Future<TankInfo> loadTankDetail(
    String tankId, {
    required SensorSnapshot snapshot,
  }) {
    requestedDetailIds.add(tankId);
    return loadDetail(tankId);
  }
}

class _LiveHomeRepository extends HomeRepository {
  @override
  bool get isLiveData => true;

  @override
  Future<HomeDashboardData> load() async => HomeDashboardData(
    tanks: const [
      HomeTankSummary(
        id: '42',
        initial: 'L',
        name: 'Live Reef',
        subtitle: 'North room',
        status: HomeOperationalStatus.normal,
        lastReportLabel: 'Updated just now',
        contextLabel: 'North room',
      ),
    ],
    attentionItems: const [],
    monitoring: const HomeMonitoringSummary(
      totalTankCount: 1,
      reportingTankCount: 1,
      outageCount: 0,
    ),
    recentActivity: const [],
    isLiveData: true,
    loadedAt: DateTime.now().toUtc(),
  );
}

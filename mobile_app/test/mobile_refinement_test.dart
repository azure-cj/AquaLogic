import 'package:aqualogic/features/alerts/data/mock_alert_repository.dart';
import 'package:aqualogic/features/alerts/screens/alerts_screen.dart';
import 'package:aqualogic/features/auth/models/auth_user.dart';
import 'package:aqualogic/features/auth/models/user_role.dart';
import 'package:aqualogic/features/control/screens/equipment_screen.dart';
import 'package:aqualogic/features/demo/demo_data.dart';
import 'package:aqualogic/features/fish/screens/fish_library_screen.dart';
import 'package:aqualogic/features/more/screens/more_screen.dart';
import 'package:aqualogic/features/sensors/data/mock_sensor_feed.dart';
import 'package:aqualogic/features/tanks/data/mock_tank_repository.dart';
import 'package:aqualogic/features/tanks/models/tank_info.dart';
import 'package:aqualogic/features/tanks/screens/tank_detail_screen.dart';
import 'package:aqualogic/features/tanks/screens/tanks_screen.dart';
import 'package:aqualogic/features/tanks/widgets/tank_overview_card.dart';
import 'package:aqualogic/shared/models/aqualogic_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tank repository keeps offline separate from critical', () {
    final tanks = const MockTankRepository(
      offlineTankIds: {'nursery-d'},
    ).list(snapshot: MockSensorFeed.snapshot(0));
    final offline = tanks.singleWhere((tank) => tank.tankId == 'nursery-d');
    final critical = tanks.singleWhere((tank) => tank.tankId == 'freshwater-c');

    expect(offline.operationalStatus, OperationalStatus.offline);
    expect(critical.operationalStatus, OperationalStatus.critical);
    expect(offline.lastReportLabel, 'No recent report');
    expect(
      offline.readings.every(
        (reading) => reading.condition == ReadingCondition.unavailable,
      ),
      isTrue,
    );
  });

  test('retired lifecycle is labeled separately from operational severity', () {
    final retired = DemoData.tanks.first.copyWith(
      lifecycle: TankLifecycle.retired,
    );

    expect(retired.lifecycleLabel, 'Retired');
    expect(retired.operationalStatus, OperationalStatus.normal);
  });

  testWidgets('retired tank cards do not collapse lifecycle into Offline', (
    tester,
  ) async {
    final retired = DemoData.tanks.first.copyWith(
      lifecycle: TankLifecycle.retired,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TankOverviewCard(tank: retired, onTap: () {}),
        ),
      ),
    );

    expect(find.text('Retired'), findsOneWidget);
    expect(find.text('Offline'), findsNothing);
  });

  test('alert repository keeps water quality and monitoring distinct', () {
    final online = const MockAlertRepository().load(
      snapshot: MockSensorFeed.snapshot(0),
    );
    expect(online.activeWaterQualityAlerts.length, 2);
    expect(online.criticalCount, 1);
    expect(online.warningCount, 1);
    expect(online.activeMonitoringIncidents, isEmpty);
    expect(online.historicalMonitoringIncidents, hasLength(1));

    final offline = const MockAlertRepository().load(
      snapshot: MockSensorFeed.snapshot(14),
    );
    expect(offline.activeWaterQualityAlerts, isEmpty);
    expect(offline.activeMonitoringIncidents, hasLength(4));
  });

  testWidgets('Alerts screen offers separate streams and safe handling copy', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AlertsScreen(
          snapshot: MockSensorFeed.snapshot(0),
          repository: const MockAlertRepository(
            monitoringOutageTankIds: {'nursery-d'},
          ),
        ),
      ),
    );

    expect(find.text('Water quality'), findsOneWidget);
    expect(find.text('1 critical'), findsOneWidget);
    expect(find.text('Mark handled'), findsWidgets);

    await tester.tap(find.text('Mark handled').first);
    await tester.pumpAndSettle();
    expect(find.text('Mark this alert as handled?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Mark handled'));
    await tester.pumpAndSettle();
    expect(find.text('0 critical'), findsOneWidget);
    expect(find.text('1 warning'), findsOneWidget);

    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Handled'), findsWidgets);
    await tester.tap(find.text('Active'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Monitoring').last);
    await tester.pumpAndSettle();
    expect(find.text('Monitoring outage'), findsNothing);
    expect(find.text('Nursery D'), findsOneWidget);
    expect(find.text('No recent readings received.'), findsOneWidget);
    expect(find.text('Mark handled'), findsNothing);
  });

  testWidgets('Fish library search opens domain-aligned species detail', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: FishLibraryScreen()));
    expect(find.text('Species directory'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'tang');
    await tester.pumpAndSettle();
    expect(find.text('Yellow Tang'), findsOneWidget);
    expect(find.text('Discus'), findsNothing);

    await tester.tap(find.text('Yellow Tang'));
    await tester.pumpAndSettle();
    expect(find.text('Species detail'), findsOneWidget);
    expect(find.text('Ideal temperature'), findsOneWidget);
    expect(find.text('Ideal pH'), findsOneWidget);
    expect(find.text('Ideal TDS'), findsOneWidget);
  });

  testWidgets('Owner equipment shows lifecycle and outcome safety', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: EquipmentScreen(
          tank: DemoData.tanks.first,
          user: const AuthUser(
            id: 'owner',
            name: 'JRed Owner',
            email: 'owner@aqualogic.local',
            role: UserRole.admin,
          ),
        ),
      ),
    );

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -1400));
    await tester.pumpAndSettle();

    for (final label in [
      'Queued',
      'Executing',
      'Succeeded',
      'Failed',
      'Expired',
      'Outcome unknown',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(
      find.text(
        'The command may have physically executed, but confirmation was not received. Check the equipment before trying again.',
      ),
      findsOneWidget,
    );

    await tester.drag(find.byType(CustomScrollView), const Offset(0, 1600));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Turn off'));
    await tester.pumpAndSettle();
    expect(find.text('Turn UV Sterilizer off?'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pump(const Duration(milliseconds: 220));
    expect(find.text('Executing'), findsWidgets);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Succeeded'), findsWidgets);
  });

  testWidgets('Owner can reach contextual equipment from Tank Detail', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TankDetailScreen(
          tank: DemoData.tanks.first,
          snapshot: MockSensorFeed.snapshot(0),
          user: const AuthUser(
            id: 'owner',
            name: 'JRed Owner',
            email: 'owner@aqualogic.local',
            role: UserRole.admin,
          ),
        ),
      ),
    );

    await tester.scrollUntilVisible(
      find.text('View equipment'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('View equipment'));
    await tester.pumpAndSettle();
    expect(find.text('Connected equipment'), findsOneWidget);
  });

  testWidgets('Staff equipment view has no writable controls', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: EquipmentScreen(
          tank: DemoData.tanks.first,
          user: const AuthUser(
            id: 'staff',
            name: 'AquaLogic Staff',
            email: 'staff@aqualogic.local',
            role: UserRole.staff,
          ),
        ),
      ),
    );

    expect(
      find.text(
        'Staff access is read-only. Equipment commands are available to Owners only.',
      ),
      findsOneWidget,
    );
    expect(find.byType(OutlinedButton), findsNothing);
  });

  testWidgets('More exposes identity and truthful app data surfaces', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MoreScreen(
          snapshot: MockSensorFeed.snapshot(0),
          user: const AuthUser(
            id: 'owner',
            name: 'JRed Owner',
            email: 'owner@aqualogic.local',
            role: UserRole.admin,
          ),
        ),
      ),
    );

    expect(find.text('JRed Owner'), findsOneWidget);
    expect(find.text('OWNER'), findsOneWidget);
    expect(find.text('Fish species'), findsOneWidget);
    expect(find.text('Sync / local data'), findsOneWidget);
    expect(find.text('About AquaLogic'), findsOneWidget);
    expect(find.text('Push notifications'), findsNothing);
    expect(find.text('Critical-only at night'), findsNothing);
  });

  testWidgets('refined mobile surfaces fit a narrow Android viewport', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(320, 640));
    const owner = AuthUser(
      id: 'owner',
      name: 'JRed Owner',
      email: 'owner@aqualogic.local',
      role: UserRole.admin,
    );
    final screens = <Widget>[
      TanksScreen(snapshot: MockSensorFeed.snapshot(0), user: owner),
      AlertsScreen(snapshot: MockSensorFeed.snapshot(0)),
      const FishLibraryScreen(),
      EquipmentScreen(tank: DemoData.tanks.first, user: owner),
      MoreScreen(snapshot: MockSensorFeed.snapshot(0), user: owner),
    ];

    for (final screen in screens) {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: screen)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });
}

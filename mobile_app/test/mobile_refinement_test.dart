import 'dart:ui' as ui;

import 'package:aqualogic/features/alerts/data/mock_alert_repository.dart';
import 'package:aqualogic/features/alerts/models/alert_info.dart';
import 'package:aqualogic/features/alerts/screens/alerts_screen.dart';
import 'package:aqualogic/features/auth/models/auth_user.dart';
import 'package:aqualogic/features/auth/models/user_role.dart';
import 'package:aqualogic/features/control/screens/equipment_screen.dart';
import 'package:aqualogic/features/demo/demo_data.dart';
import 'package:aqualogic/features/fish/screens/fish_library_screen.dart';
import 'package:aqualogic/features/more/screens/more_screen.dart';
import 'package:aqualogic/features/sensors/data/mock_sensor_feed.dart';
import 'package:aqualogic/features/sensors/models/sensor_snapshot.dart';
import 'package:aqualogic/features/tanks/data/mock_tank_repository.dart';
import 'package:aqualogic/features/tanks/models/tank_info.dart';
import 'package:aqualogic/features/tanks/screens/tank_detail_screen.dart';
import 'package:aqualogic/features/tanks/screens/tanks_screen.dart';
import 'package:aqualogic/features/tanks/widgets/tank_overview_card.dart';
import 'package:aqualogic/shared/models/aqualogic_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('alert-summary-count-critical')),
          )
          .data,
      '1',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('alert-summary-count-warning')),
          )
          .data,
      '1',
    );
    expect(find.text('Mark handled'), findsWidgets);

    await tester.tap(find.text('Mark handled').first);
    await tester.pumpAndSettle();
    expect(find.text('Mark this alert as handled?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Mark handled'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('alert-summary-count-critical')),
          )
          .data,
      '0',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('alert-summary-count-warning')),
          )
          .data,
      '1',
    );

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

  testWidgets('Alerts keeps its Material surface on a standalone route', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: AlertsScreen(snapshot: MockSensorFeed.snapshot(0))),
    );

    final title = tester.renderObject<RenderParagraph>(
      find.byKey(const ValueKey('alerts-page-title')),
    );
    expect(title.text.style?.decoration, TextDecoration.none);
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      const Color(0xFFEAF8FA),
    );

    await tester.tap(find.byKey(const ValueKey('alert-state-history')));
    await tester.pumpAndSettle();
    expect(find.text('Display Reef A'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Alerts uses explicit actions and preserves exact alert routing',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: AlertsScreen(snapshot: MockSensorFeed.snapshot(0))),
      );

      expect(find.byKey(const ValueKey('alert-summary-strip')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('alert-stream-selector')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('alert-state-tabs')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('alert-view-freshwater-c-tds')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Mark Freshwater C alert as handled'),
        findsOneWidget,
      );
      final streamSemantics = tester.getSemantics(
        find.byKey(const ValueKey('alert-stream-waterQuality')),
      );
      expect(streamSemantics.flagsCollection.isSelected, ui.Tristate.isTrue);

      await tester.tap(
        find.byKey(const ValueKey('alert-view-freshwater-c-tds')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Alert detail'), findsOneWidget);
      expect(find.text('Freshwater C'), findsOneWidget);
      expect(find.text('TDS'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('alert-view-quarantine-b-ph')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('alert-view-quarantine-b-ph')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Quarantine B'), findsOneWidget);
      expect(find.text('pH'), findsOneWidget);
    },
  );

  testWidgets('Monitoring rows open the exact monitoring context', (
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

    await tester.tap(find.byKey(const ValueKey('alert-stream-monitoring')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('monitoring-incident-nursery-d-monitoring')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nursery D'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('monitoring-row-nursery-d-monitoring')),
      findsOneWidget,
    );
    expect(find.text('Offline'), findsOneWidget);
  });

  testWidgets('Alerts empty states stay calm across both streams and views', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AlertsScreen(
          snapshot: MockSensorFeed.snapshot(0),
          repository: const _EmptyAlertRepository(),
        ),
      ),
    );

    expect(find.text('No active water-quality alerts.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('alert-stream-monitoring')));
    await tester.pumpAndSettle();
    expect(find.text('No monitoring outages.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('alert-state-history')));
    await tester.pumpAndSettle();
    expect(find.text('No alert history yet.'), findsOneWidget);
  });

  testWidgets('Alerts remains usable at larger text scales', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(360, 720));

    for (final scale in [1.0, 1.3, 1.5, 2.0]) {
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: MaterialApp(
            home: AlertsScreen(snapshot: MockSensorFeed.snapshot(0)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'scale $scale');
      expect(
        find.byKey(const ValueKey('alert-stream-selector')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('alert-state-tabs')), findsOneWidget);
      expect(find.text('View alert'), findsWidgets);
      expect(find.text('Mark handled'), findsWidgets);
    }
  });

  testWidgets('Alerts fits the requested mobile viewports', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final size in [
      const Size(360, 720),
      const Size(390, 680),
      const Size(390, 844),
      const Size(430, 932),
    ]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        MaterialApp(home: AlertsScreen(snapshot: MockSensorFeed.snapshot(0))),
      );
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isNull,
        reason: '${size.width}x${size.height}',
      );
      expect(find.text('Alerts'), findsOneWidget);
      expect(find.text('View alert'), findsWidgets);
      expect(find.text('Mark handled'), findsWidgets);
    }
  });

  testWidgets('Alerts focuses an exact monitoring incident reference', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AlertsScreen(
          snapshot: MockSensorFeed.snapshot(0),
          repository: const MockAlertRepository(
            monitoringOutageTankIds: {'nursery-d'},
          ),
          initialReferenceId: 'nursery-d-monitoring',
          initialStream: AlertStream.monitoring,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nursery D'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('monitoring-incident-nursery-d-monitoring')),
      findsOneWidget,
    );
  });

  testWidgets('Alerts opens an exact historical alert reference', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AlertsScreen(
          snapshot: MockSensorFeed.snapshot(0),
          initialReferenceId: 'display-reef-a-temp-history',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Alert detail'), findsOneWidget);
    expect(find.text('Display Reef A'), findsWidgets);
    expect(find.text('Temperature'), findsOneWidget);
    expect(find.text('Handled'), findsOneWidget);
  });

  testWidgets('Alerts reports a missing initial reference gracefully', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AlertsScreen(
          snapshot: MockSensorFeed.snapshot(0),
          initialReferenceId: 'missing-alert-id',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('This alert is no longer available.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Tanks directory keeps dynamic counts and filter behavior', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TanksScreen(snapshot: MockSensorFeed.snapshot(0))),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('tanks-page-title')), findsOneWidget);
    expect(find.text('Monitor your aquarium fleet'), findsOneWidget);
    expect(find.text('Search tanks...'), findsOneWidget);
    expect(find.text('4 tanks · 2 need attention'), findsOneWidget);
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Attention'), findsOneWidget);
    expect(find.text('Offline'), findsOneWidget);
    expect(find.text('Display Reef A'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tank-filter-attention')));
    await tester.pumpAndSettle();
    expect(find.text('Freshwater C'), findsOneWidget);
    expect(find.text('Quarantine B'), findsOneWidget);
    expect(find.text('Display Reef A'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('tank-filter-offline')));
    await tester.pumpAndSettle();
    expect(find.text('No tanks are offline'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tank-filter-all')));
    await tester.enterText(find.byType(TextField), 'nursery');
    await tester.pumpAndSettle();
    expect(find.text('Nursery D'), findsOneWidget);
    expect(find.text('Display Reef A'), findsNothing);
  });

  testWidgets('Tank detail uses a shared sensor panel and compact sections', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TankDetailScreen(
          tank: DemoData.tanks.first,
          snapshot: MockSensorFeed.snapshot(0),
        ),
      ),
    );

    expect(find.text('Display Reef A'), findsOneWidget);
    expect(find.text('Location'), findsOneWidget);
    expect(find.text('Main room'), findsOneWidget);
    expect(find.text('320L'), findsOneWidget);
    expect(find.byKey(const ValueKey('sensor-overview-panel')), findsOneWidget);
    expect(find.text('Temperature'), findsOneWidget);
    expect(find.text('26.8'), findsOneWidget);
    expect(find.text('TDS'), findsOneWidget);
    expect(find.text('2,620'), findsOneWidget);
    expect(find.text('1,080'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Issues'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.drag(find.byType(CustomScrollView).last, const Offset(0, -80));
    await tester.pumpAndSettle();
    expect(find.text('No active issues'), findsOneWidget);
    expect(find.text('Reporting normally'), findsOneWidget);
    expect(find.text('4 connected devices'), findsOneWidget);
    expect(find.text('Recent activity'), findsOneWidget);
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
      find.byKey(const ValueKey('tank-equipment-entry')),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const ValueKey('tank-equipment-entry')));
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
    final semanticsHandle = tester.ensureSemantics();
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

    expect(find.byKey(const ValueKey('more-page-title')), findsOneWidget);
    expect(find.text('Account, app settings, and resources'), findsOneWidget);
    expect(find.text('JRed Owner'), findsOneWidget);
    expect(find.text('owner@aqualogic.local'), findsOneWidget);
    expect(find.text('JRed Aquatics'), findsOneWidget);
    expect(find.text('Authenticated AquaLogic account'), findsOneWidget);
    expect(find.text('OWNER'), findsOneWidget);
    expect(find.text('Fish species'), findsOneWidget);
    expect(find.text('Sync / local data'), findsOneWidget);
    expect(find.text('Local data and connection status'), findsOneWidget);
    expect(find.text('About AquaLogic'), findsOneWidget);
    expect(
      find.text('Product information and prototype scope'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('account-profile-panel')), findsOneWidget);
    expect(find.byKey(const ValueKey('more-app-data-group')), findsOneWidget);
    expect(find.text('Session'), findsNothing);
    expect(find.text('Sign out'), findsOneWidget);
    expect(find.bySemanticsLabel('Sign out'), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        'Open Fish species. Care references and suitability context',
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        'Open Sync / local data. Local data and connection status',
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        'Open About AquaLogic. Product information and prototype scope',
      ),
      findsOneWidget,
    );
    semanticsHandle.dispose();
    expect(find.text('Push notifications'), findsNothing);
    expect(find.text('Critical-only at night'), findsNothing);
  });

  testWidgets('More keeps account and resource destinations intact', (
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

    await tester.tap(find.byKey(const ValueKey('account-profile-panel')));
    await tester.pumpAndSettle();
    expect(find.text('Your authenticated AquaLogic identity'), findsOneWidget);
    expect(find.text('Session'), findsNothing);
    expect(
      find.byKey(const ValueKey('account-sign-out-button')),
      findsOneWidget,
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Fish species'));
    await tester.pumpAndSettle();
    expect(
      find.text('Practical care references for your tanks'),
      findsOneWidget,
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sync / local data'));
    await tester.pumpAndSettle();
    expect(find.text('Local demo data'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    await tester.tap(find.text('About AquaLogic'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'A local-first aquarium monitoring and operations experience for JRed Aquatics.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('More remains usable across mobile sizes and text scales', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const owner = AuthUser(
      id: 'owner',
      name: 'A long AquaLogic owner name',
      email: 'owner-with-a-long-email-address@aqualogic.local',
      role: UserRole.admin,
    );

    for (final size in [
      const Size(360, 720),
      const Size(390, 680),
      const Size(390, 844),
      const Size(430, 932),
    ]) {
      await tester.binding.setSurfaceSize(size);
      for (final scale in [1.0, 1.3, 1.5, 2.0]) {
        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: MaterialApp(
              home: MoreScreen(
                snapshot: MockSensorFeed.snapshot(0),
                user: owner,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: '${size.width}x${size.height} at $scale',
        );
        expect(find.text('Sign out'), findsOneWidget);
      }
    }
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
      TankDetailScreen(
        tank: DemoData.tanks.first,
        snapshot: MockSensorFeed.snapshot(0),
        user: owner,
      ),
      AlertsScreen(snapshot: MockSensorFeed.snapshot(0)),
      const FishLibraryScreen(),
      EquipmentScreen(tank: DemoData.tanks.first, user: owner),
      MoreScreen(snapshot: MockSensorFeed.snapshot(0), user: owner),
    ];

    for (final screen in screens) {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: screen)));
      await tester.pumpAndSettle();
      final exception = tester.takeException();
      expect(exception, isNull, reason: screen.runtimeType.toString());
    }
  });
}

class _EmptyAlertRepository implements AlertRepository {
  const _EmptyAlertRepository();

  @override
  AlertCenterData load({required SensorSnapshot snapshot}) {
    return const AlertCenterData(
      waterQualityAlerts: <AlertInfo>[],
      monitoringIncidents: <MonitoringIncident>[],
    );
  }
}

import 'package:aqualogic/features/auth/models/auth_user.dart';
import 'package:aqualogic/features/auth/models/user_role.dart';
import 'package:aqualogic/features/home/data/mock_home_repository.dart';
import 'package:aqualogic/features/home/models/home_dashboard_data.dart';
import 'package:aqualogic/features/home/screens/home_screen.dart';
import 'package:aqualogic/features/home/widgets/home_shared_widgets.dart';
import 'package:aqualogic/features/home/widgets/staff_home_content.dart';
import 'package:aqualogic/features/sensors/data/mock_sensor_feed.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Home data uses backend-compatible operational statuses', () {
    final data = const MockHomeRepository().load(
      snapshot: MockSensorFeed.snapshot(0),
    );

    expect(data.normalTankCount, 2);
    expect(data.needsAttentionCount, 2);
    expect(data.offlineTankCount, 0);
    expect(data.attentionItems.first.status, HomeOperationalStatus.critical);
    expect(data.attentionItems.first.type, HomeAttentionType.waterQuality);
    expect(data.monitoring.reportingTankCount, 4);
    expect(data.monitoring.outageCount, 0);
  });

  testWidgets('fleet status headline follows the current fleet state', (
    tester,
  ) async {
    const data = HomeDashboardData(
      tanks: [
        HomeTankSummary(
          id: 'display-reef-a',
          initial: 'D',
          name: 'Display Reef A',
          subtitle: 'Mixed reef - 320L',
          status: HomeOperationalStatus.normal,
          lastReportLabel: 'Updated just now',
          contextLabel: 'Ready for routine checks',
        ),
      ],
      attentionItems: [],
      monitoring: HomeMonitoringSummary(
        totalTankCount: 1,
        reportingTankCount: 1,
        outageCount: 0,
        sensorFeedOnline: true,
      ),
      recentActivity: [],
    );

    await tester.pumpWidget(
      const MaterialApp(home: FleetStatusSheet(data: data)),
    );

    expect(find.text('All tanks look good'), findsOneWidget);
    expect(
      find.text('1 tank · 1 normal · 0 need attention · 0 offline'),
      findsOneWidget,
    );
  });

  test('offline tanks remain distinct from critical water-quality states', () {
    final data = const MockHomeRepository(
      offlineTankIds: {'nursery-d'},
    ).load(snapshot: MockSensorFeed.snapshot(0));

    final offlineTank = data.tanks.singleWhere(
      (tank) => tank.id == 'nursery-d',
    );
    final offlineAttention = data.attentionItems.singleWhere(
      (item) => item.tankId == 'nursery-d',
    );

    expect(offlineTank.status, HomeOperationalStatus.offline);
    expect(offlineTank.lastReportLabel, 'No recent report');
    expect(offlineAttention.status, HomeOperationalStatus.offline);
    expect(offlineAttention.type, HomeAttentionType.monitoring);
    expect(data.monitoring.reportingTankCount, 3);
    expect(data.monitoring.outageCount, 1);
  });

  test(
    'an unavailable local sensor feed does not become critical water quality',
    () {
      final data = const MockHomeRepository().load(
        snapshot: MockSensorFeed.snapshot(14),
      );

      expect(data.monitoring.sensorFeedOnline, isFalse);
      expect(data.monitoring.reportingTankCount, 0);
      expect(data.monitoring.outageCount, 4);
      expect(
        data.tanks.every(
          (tank) => tank.status == HomeOperationalStatus.offline,
        ),
        isTrue,
      );
      expect(
        data.attentionItems.every(
          (item) => item.status == HomeOperationalStatus.offline,
        ),
        isTrue,
      );
    },
  );

  testWidgets('Staff Home has a calm all-normal empty state', (tester) async {
    const data = HomeDashboardData(
      tanks: [
        HomeTankSummary(
          id: 'display-reef-a',
          initial: 'D',
          name: 'Display Reef A',
          subtitle: 'Mixed reef - 320L',
          status: HomeOperationalStatus.normal,
          lastReportLabel: 'Updated just now',
          contextLabel: 'Ready for routine checks',
        ),
      ],
      attentionItems: [],
      monitoring: HomeMonitoringSummary(
        totalTankCount: 1,
        reportingTankCount: 1,
        outageCount: 0,
        sensorFeedOnline: true,
      ),
      recentActivity: [],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SingleChildScrollView(
          child: StaffHomeContent(
            data: data,
            onOpenAlerts: _noop,
            onOpenTanks: _noop,
          ),
        ),
      ),
    );

    expect(find.text('Nothing needs immediate attention'), findsOneWidget);
    expect(
      find.text('All monitored tanks are currently normal.'),
      findsOneWidget,
    );
  });

  testWidgets('Owner Home remains usable at common mobile widths', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final size in const [Size(320, 640), Size(411, 915)]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            snapshot: MockSensorFeed.snapshot(0),
            user: const AuthUser(
              id: 'owner',
              name: 'JRed Owner',
              email: 'owner@aqualogic.local',
              role: UserRole.admin,
            ),
            onOpenAlerts: _noop,
            onOpenTanks: _noop,
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(HomeHero), findsOneWidget);
      expect(
        find.byKey(const ValueKey('home-hero-illustration')),
        findsOneWidget,
      );
      expect(find.text('2 tanks need attention'), findsOneWidget);
      expect(find.text('Fleet overview'), findsOneWidget);
    }
  });
}

void _noop() {}

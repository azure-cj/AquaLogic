import 'dart:async';

import 'package:aqualogic/features/auth/models/auth_user.dart';
import 'package:aqualogic/features/auth/models/user_role.dart';
import 'package:aqualogic/features/home/data/home_repository.dart';
import 'package:aqualogic/features/home/models/home_dashboard_data.dart';
import 'package:aqualogic/features/home/screens/home_screen.dart';
import 'package:aqualogic/shared/network/api_failure.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Home uses a structured loading state while the first request waits',
    (tester) async {
      final completer = Completer<HomeDashboardData>();
      final repository = _SequenceHomeRepository([
        () => completer.future,
      ], isLiveData: true);

      await tester.pumpWidget(_home(repository, role: UserRole.admin));
      await tester.pump();

      expect(
        find.byKey(const ValueKey('home-loading-content')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('fleet-status-loading')),
        findsOneWidget,
      );
      expect(find.text('Offline'), findsNothing);

      completer.complete(_data(isLiveData: true));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('home-loading-content')), findsNothing);
      expect(find.text('Fleet overview'), findsOneWidget);
    },
  );

  testWidgets(
    'Home shows a connection error and Retry without tank offline state',
    (tester) async {
      final repository = _SequenceHomeRepository([
        () async => throw ApiFailure.networkUnavailable(),
        () async => _data(),
      ]);

      await tester.pumpWidget(_home(repository, role: UserRole.admin));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('home-load-error')), findsOneWidget);
      expect(find.text("Couldn't load Home from AquaLogic"), findsOneWidget);
      expect(find.text('1 tank offline'), findsNothing);
      expect(find.text('Offline'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('home-load-retry')));
      await tester.pumpAndSettle();

      expect(repository.loadCount, 2);
      expect(find.byKey(const ValueKey('home-load-error')), findsNothing);
      expect(find.text('Live Display Reef'), findsWidgets);
      expect(find.byKey(const ValueKey('fleet-status-sheet')), findsOneWidget);
    },
  );

  testWidgets('partial Home data is labeled and never shows demo activity', (
    tester,
  ) async {
    final repository = _SequenceHomeRepository([
      () async => _data(alertsAvailable: false, isLiveData: true),
    ], isLiveData: true);

    await tester.pumpWidget(_home(repository, role: UserRole.admin));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Water-quality alert details could not be loaded'),
      findsOneWidget,
    );
    expect(find.text('Fleet overview'), findsOneWidget);
    expect(find.text('Recent activity'), findsNothing);
    expect(find.text('Feeding completed'), findsNothing);
    expect(find.text('View all alerts'), findsNothing);
    expect(find.text('Details in M4'), findsNothing);
  });

  testWidgets('Owner and Staff retain distinct live Home hierarchy', (
    tester,
  ) async {
    final ownerRepository = _SequenceHomeRepository([
      () async => _data(isLiveData: true),
    ], isLiveData: true);
    await tester.pumpWidget(_home(ownerRepository, role: UserRole.admin));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('fleet-status-sheet')), findsOneWidget);
    expect(find.text('Fleet overview'), findsOneWidget);
    expect(find.text('Live Display Reef'), findsWidgets);
    expect(find.text('Recent activity'), findsNothing);

    final staffRepository = _SequenceHomeRepository([
      () async => _data(isLiveData: true),
    ], isLiveData: true);
    await tester.pumpWidget(_home(staffRepository, role: UserRole.staff));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('fleet-status-sheet')), findsNothing);
    expect(find.text('Tank rounds'), findsOneWidget);
    expect(find.text('Fleet overview'), findsNothing);
    expect(find.textContaining('Room A · Just now'), findsOneWidget);
    expect(find.text('Recent activity'), findsNothing);
  });

  testWidgets('stale Home refreshes on resume, fresh Home does not poll', (
    tester,
  ) async {
    final repository = _SequenceHomeRepository([
      () async => _data(
        loadedAt: DateTime.now().toUtc().subtract(const Duration(minutes: 2)),
      ),
      () async => _data(),
    ], isLiveData: true);

    await tester.pumpWidget(_home(repository, role: UserRole.staff));
    await tester.pumpAndSettle();
    expect(repository.loadCount, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(repository.loadCount, 2);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(repository.loadCount, 2);
  });

  testWidgets('pull to refresh reloads Home without periodic polling', (
    tester,
  ) async {
    final repository = _SequenceHomeRepository([
      () async => _data(),
      () async => _data(),
    ], isLiveData: true);

    await tester.pumpWidget(_home(repository, role: UserRole.admin));
    await tester.pumpAndSettle();
    expect(repository.loadCount, 1);

    await tester.dragFrom(const Offset(180, 130), const Offset(0, 440));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(repository.loadCount, 2);
  });
}

Widget _home(_SequenceHomeRepository repository, {required UserRole role}) =>
    MaterialApp(
      home: Scaffold(
        body: HomeScreen(
          user: AuthUser(
            id: '42',
            name: role == UserRole.admin ? 'Owner User' : 'Staff User',
            email: 'user@aqualogic.test',
            role: role,
          ),
          repository: repository,
          onOpenAlerts: _noop,
          onOpenTanks: _noop,
        ),
      ),
    );

HomeDashboardData _data({
  bool alertsAvailable = true,
  bool monitoringIncidentsAvailable = true,
  bool isLiveData = false,
  DateTime? loadedAt,
}) => HomeDashboardData(
  tanks: const [
    HomeTankSummary(
      id: '42',
      initial: 'L',
      name: 'Live Display Reef',
      subtitle: 'Room A',
      status: HomeOperationalStatus.normal,
      lastReportedAt: null,
      reportingAgeSeconds: 12,
      lastReportLabel: 'Updated just now',
      contextLabel: 'Room A',
    ),
  ],
  attentionItems: const [],
  monitoring: HomeMonitoringSummary(
    totalTankCount: 1,
    reportingTankCount: 1,
    outageCount: 0,
  ),
  recentActivity: const [],
  alertsAvailable: alertsAvailable,
  monitoringIncidentsAvailable: monitoringIncidentsAvailable,
  isLiveData: isLiveData,
  loadedAt: loadedAt ?? DateTime.now().toUtc(),
);

class _SequenceHomeRepository extends HomeRepository {
  _SequenceHomeRepository(this._steps, {this.isLiveData = false});

  final List<Future<HomeDashboardData> Function()> _steps;
  @override
  final bool isLiveData;
  var loadCount = 0;

  @override
  Future<HomeDashboardData> load() {
    loadCount += 1;
    final index = loadCount - 1;
    if (index >= _steps.length) return _steps.last();
    return _steps[index]();
  }
}

void _noop() {}

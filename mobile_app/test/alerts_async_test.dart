import 'dart:async';
import 'dart:ui' as ui;

import 'package:aqualogic/app/navigation/aqualogic_shell.dart';
import 'package:aqualogic/features/alerts/data/mock_alert_repository.dart';
import 'package:aqualogic/features/alerts/models/alert_info.dart';
import 'package:aqualogic/features/alerts/screens/alert_detail_screen.dart';
import 'package:aqualogic/features/alerts/screens/alerts_screen.dart';
import 'package:aqualogic/features/auth/models/auth_user.dart';
import 'package:aqualogic/features/auth/models/user_role.dart';
import 'package:aqualogic/features/home/data/home_repository.dart';
import 'package:aqualogic/features/home/models/home_dashboard_data.dart';
import 'package:aqualogic/features/sensors/data/mock_sensor_feed.dart';
import 'package:aqualogic/features/sensors/models/sensor_snapshot.dart';
import 'package:aqualogic/features/tanks/data/mock_tank_repository.dart';
import 'package:aqualogic/features/tanks/models/tank_info.dart';
import 'package:aqualogic/shared/network/api_failure.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Incident Center loads all stream/state combinations and retries partial failure',
    (tester) async {
      final waterActiveResult = Completer<List<AlertInfo>>();
      final monitoringActiveResult = Completer<MonitoringIncidentPage>();
      var monitoringActiveCalls = 0;
      final repository = _ScriptedAlertRepository(
        waterLoader: ({required history}) async => history
            ? [_handledAlert, _automaticAlert]
            : waterActiveResult.future,
        monitoringLoader:
            ({required history, required page, required pageSize}) {
              if (history) {
                return Future.value(
                  _page([_disabledIncident], page: page, total: 1),
                );
              }
              monitoringActiveCalls++;
              return monitoringActiveCalls == 1
                  ? monitoringActiveResult.future
                  : Future.value(
                      _page([_activeIncident], page: page, total: 1),
                    );
            },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: AlertsScreen(
            snapshot: MockSensorFeed.snapshot(0),
            repository: repository,
          ),
        ),
      );
      await tester.pump();
      expect(
        find.byKey(
          const ValueKey('alerts-loading-loading-water-quality-alerts'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('alert-stream-monitoring')));
      await tester.pump();
      expect(
        find.byKey(
          const ValueKey('alerts-loading-loading-monitoring-incidents'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('alert-stream-waterQuality')));
      await tester.pump();

      waterActiveResult.complete([_activeAlert]);
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('alert-view-901')), findsOneWidget);

      monitoringActiveResult.completeError(ApiFailure.networkUnavailable());
      await tester.pumpAndSettle();
      expect(find.text('Backend alert record 901'), findsOneWidget);
      expect(
        find.text(
          'Monitoring data could not be loaded. Water-quality alerts remain available.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('alert-stream-monitoring')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          "Can't connect to AquaLogic. Check your connection and try again.",
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('alerts-source-retry')));
      await tester.pumpAndSettle();
      expect(monitoringActiveCalls, 2);
      expect(find.text('Backend Tank Eight'), findsOneWidget);
      expect(find.text('Monitoring disabled'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('alert-state-history')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('monitoring-incident-702')),
        findsOneWidget,
      );
      expect(find.text('Monitoring disabled'), findsWidgets);

      await tester.tap(find.byKey(const ValueKey('alert-stream-waterQuality')));
      await tester.pumpAndSettle();
      expect(find.text('Handled'), findsWidgets);
      expect(find.text('Resolved automatically'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('alert-state-active')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('alert-view-901')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('alert-stream-monitoring')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('alert-state-history')));
      await tester.pumpAndSettle();
      final refresh = tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh;
      await refresh();
      await tester.pumpAndSettle();
      expect(_isSelected(tester, 'alert-stream-monitoring'), isTrue);
      expect(_isSelected(tester, 'alert-state-history'), isTrue);
    },
  );

  testWidgets(
    'failed reference lookup stays an API error instead of claiming not found',
    (tester) async {
      final repository = _ScriptedAlertRepository(
        waterLoader: ({required history}) async =>
            throw ApiFailure.networkUnavailable(),
        monitoringLoader:
            ({required history, required page, required pageSize}) async =>
                _page(const [], page: page, total: 0),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: AlertsScreen(
            snapshot: MockSensorFeed.snapshot(0),
            repository: repository,
            initialReferenceId: '991',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          "Can't connect to AquaLogic. Check your connection and try again.",
        ),
        findsOneWidget,
      );
      expect(find.text('This alert is no longer available.'), findsNothing);
      expect(find.byKey(const ValueKey('alerts-source-retry')), findsOneWidget);
    },
  );

  testWidgets(
    'monitoring Home reference pages to and opens the exact incident',
    (tester) async {
      final requestedPages = <int>[];
      final repository = _ScriptedAlertRepository(
        waterLoader: ({required history}) async => const [],
        monitoringLoader:
            ({required history, required page, required pageSize}) async {
              requestedPages.add(page);
              if (history) {
                return _page([_disabledIncident], page: page, total: 1);
              }
              if (page == 1) {
                return _page(
                  [_activeIncident],
                  page: 1,
                  total: 2,
                  hasNext: true,
                );
              }
              return _page([_secondIncident], page: 2, total: 2);
            },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: AlertsScreen(
            snapshot: MockSensorFeed.snapshot(0),
            repository: repository,
            initialStream: AlertStream.monitoring,
            initialReferenceId: '702',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(requestedPages, [1, 2]);
      expect(_isSelected(tester, 'alert-stream-monitoring'), isTrue);
      expect(_isSelected(tester, 'alert-state-active'), isTrue);
      expect(
        find.byKey(const ValueKey('monitoring-incident-702')),
        findsOneWidget,
      );
      expect(find.text('Backend Tank Nine'), findsWidgets);
      expect(
        find.text('Monitoring incident · reporting state, not water quality'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'monitoring next-page failure keeps loaded incidents and retry advances the page',
    (tester) async {
      var pageTwoCalls = 0;
      final repository = _ScriptedAlertRepository(
        waterLoader: ({required history}) async => const [],
        monitoringLoader:
            ({required history, required page, required pageSize}) async {
              if (history) return _page(const [], page: page, total: 0);
              if (page == 1) {
                return _page(
                  [_activeIncident],
                  page: 1,
                  total: 2,
                  hasNext: true,
                );
              }
              pageTwoCalls++;
              if (pageTwoCalls == 1) throw ApiFailure.networkUnavailable();
              return _page([_secondIncident], page: 2, total: 2);
            },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: AlertsScreen(
            snapshot: MockSensorFeed.snapshot(0),
            repository: repository,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('alert-stream-monitoring')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('monitoring-incident-701')),
        findsOneWidget,
      );

      await tester.ensureVisible(
        find.byKey(const ValueKey('monitoring-load-more')),
      );
      await tester.tap(find.byKey(const ValueKey('monitoring-load-more')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('monitoring-incident-701')),
        findsOneWidget,
      );
      expect(
        find.text(
          "Can't connect to AquaLogic. Check your connection and try again.",
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('alerts-source-retry')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('alerts-source-retry')));
      await tester.pumpAndSettle();
      expect(pageTwoCalls, 2);
      expect(
        find.byKey(const ValueKey('monitoring-incident-701')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('monitoring-incident-702')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('monitoring-load-more')), findsNothing);
    },
  );

  testWidgets(
    'Mark handled disables duplicate submission and moves alert into history',
    (tester) async {
      final resolveResult = Completer<AlertInfo>();
      var handled = false;
      var resolveCalls = 0;
      final repository = _ScriptedAlertRepository(
        waterLoader: ({required history}) async => history
            ? (handled ? [_handledAlert] : const [])
            : (handled ? const [] : [_activeAlert]),
        monitoringLoader:
            ({required history, required page, required pageSize}) async =>
                _page(const [], page: page, total: 0),
        resolveLoader: (id) {
          resolveCalls++;
          return resolveResult.future.then((alert) {
            handled = true;
            return alert;
          });
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: AlertsScreen(
            snapshot: MockSensorFeed.snapshot(0),
            repository: repository,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final handleButton = find.byKey(const ValueKey('alert-handle-901'));
      await tester.ensureVisible(handleButton);
      await tester.tap(handleButton);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Mark handled'),
        ),
      );
      await tester.pump();

      expect(resolveCalls, 1);
      expect(find.text('Saving'), findsOneWidget);
      expect(tester.widget<TextButton>(handleButton).onPressed, isNull);

      resolveResult.complete(_handledAlert);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('alert-handle-901')), findsNothing);
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('alert-summary-count-critical')),
            )
            .data,
        '0',
      );

      await tester.tap(find.byKey(const ValueKey('alert-state-history')));
      await tester.pumpAndSettle();
      expect(find.text('Handled'), findsWidgets);
      expect(find.textContaining('water condition recovered'), findsNothing);
    },
  );

  testWidgets(
    'Alert Detail updates in place with truthful handled and automatic wording',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AlertDetailScreen(
            alert: _handledAlert,
            snapshot: MockSensorFeed.snapshot(0),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Handled'), findsWidgets);
      expect(find.text('Operator acknowledgement'), findsOneWidget);
      expect(
        find.textContaining(
          'does not confirm that the water condition recovered',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('water recovered'), findsNothing);

      await tester.pumpWidget(
        MaterialApp(
          home: AlertDetailScreen(
            alert: _automaticAlert,
            snapshot: MockSensorFeed.snapshot(0),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Resolved automatically'), findsWidgets);
      expect(find.text('Automatic backend resolution'), findsOneWidget);
      expect(find.textContaining('operator marked it handled'), findsOneWidget);
      expect(find.textContaining('water recovered'), findsNothing);
    },
  );

  testWidgets(
    'Home, Incident Center, and Tank Detail open the same live alert and refresh after handling',
    (tester) async {
      final alertRepository = _LinkedAlertRepository();
      final homeRepository = _LinkedHomeRepository(alertRepository);
      final tankRepository = _LinkedTankRepository(alertRepository);

      await tester.pumpWidget(
        MaterialApp(
          home: AquaLogicShell(
            user: _staff,
            homeRepository: homeRepository,
            tankRepository: tankRepository,
            alertRepository: alertRepository,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('View alert').first);
      await tester.pumpAndSettle();
      expect(find.text('Backend alert record 901'), findsOneWidget);
      expect(alertRepository.lookupIds, ['901']);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('soft-floating-dock-destination-2')),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('alert-view-901')));
      await tester.tap(find.byKey(const ValueKey('alert-view-901')));
      await tester.pumpAndSettle();
      expect(find.text('Backend alert record 901'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      // The existing scroll behavior intentionally hides the floating dock
      // after the detail CTA scrolls into view. Scroll upward to restore it.
      await tester.fling(
        find.byType(CustomScrollView).first,
        const Offset(0, 700),
        1200,
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('soft-floating-dock-destination-1')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tank-card-8')));
      await tester.pumpAndSettle();
      expect(find.text('Issues'), findsOneWidget);
      expect(find.text('Backend alert record 901'), findsOneWidget);
      await tester.ensureVisible(find.text('View alert'));
      await tester.tap(find.text('View alert').first);
      await tester.pumpAndSettle();
      expect(find.text('Backend alert record 901'), findsOneWidget);
      expect(alertRepository.lookupIds, ['901', '901']);

      await tester.tap(find.byKey(const ValueKey('alert-detail-mark-handled')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Mark handled'),
        ),
      );
      await tester.pumpAndSettle();
      expect(alertRepository.resolveCalls, 1);
      expect(find.text('Handled'), findsWidgets);
      expect(find.text('Operator acknowledgement'), findsOneWidget);
      expect(find.textContaining('water condition recovered'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('No active issues'), findsOneWidget);
      expect(tankRepository.detailLoads, 2);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('soft-floating-dock-destination-0')),
      );
      await tester.pumpAndSettle();
      expect(homeRepository.loads, greaterThanOrEqualTo(2));
      expect(find.byKey(const ValueKey('owner-priority-card')), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey('soft-floating-dock-destination-2')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('alert-view-901')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('alert-state-history')));
      await tester.pumpAndSettle();
      expect(find.text('Handled'), findsWidgets);
      expect(find.textContaining('water recovered'), findsNothing);
    },
  );
}

bool _isSelected(WidgetTester tester, String key) =>
    tester.getSemantics(find.byKey(ValueKey(key))).flagsCollection.isSelected ==
    ui.Tristate.isTrue;

MonitoringIncidentPage _page(
  List<MonitoringIncident> items, {
  required int page,
  required int total,
  bool hasNext = false,
}) => MonitoringIncidentPage(
  items: items,
  page: page,
  pageSize: 25,
  total: total,
  totalPages: hasNext ? page + 1 : (total == 0 ? 0 : page),
  hasNext: hasNext,
);

final _activeAlert = AlertInfo(
  id: '901',
  tankId: '8',
  tankName: 'Backend Tank Eight',
  parameter: 'pH',
  severity: AlertSeverity.critical,
  message: 'Backend alert record 901',
  startedLabel: 'Started Sep 25',
  startedAt: DateTime.utc(2026, 9, 25, 8),
  lifecycle: AlertLifecycle.active,
);

final _handledAlert = _activeAlert.copyWith(
  lifecycle: AlertLifecycle.handled,
  resolvedAt: DateTime.utc(2026, 9, 25, 9),
  resolvedByUserId: 11,
  resolutionSource: AlertResolutionSource.operator,
);

final _automaticAlert = AlertInfo(
  id: '902',
  tankId: '8',
  tankName: 'Backend Tank Eight',
  parameter: 'TDS',
  severity: AlertSeverity.warning,
  message: 'Backend system resolved record 902',
  startedLabel: 'Started Sep 24',
  startedAt: DateTime.utc(2026, 9, 24, 8),
  resolvedAt: DateTime.utc(2026, 9, 24, 9),
  resolutionSource: AlertResolutionSource.system,
  lifecycle: AlertLifecycle.resolvedAutomatically,
);

const _activeIncident = MonitoringIncident(
  id: '701',
  tankId: '8',
  tankName: 'Backend Tank Eight',
  message: 'No recent sensor report received.',
  startedLabel: 'Started Sep 25',
  status: MonitoringIncidentStatus.active,
  durationSeconds: 1200,
);

const _secondIncident = MonitoringIncident(
  id: '702',
  tankId: '9',
  tankName: 'Backend Tank Nine',
  message: 'No recent sensor report received.',
  startedLabel: 'Started Sep 24',
  status: MonitoringIncidentStatus.active,
  durationSeconds: 1800,
);

const _disabledIncident = MonitoringIncident(
  id: '702',
  tankId: '9',
  tankName: 'Backend Tank Nine',
  message: 'Monitoring was disabled for this tank.',
  startedLabel: 'Started Sep 24',
  status: MonitoringIncidentStatus.resolved,
  resolutionReason: MonitoringResolutionReason.monitoringDisabled,
  recoveredLabel: 'Resolved Sep 25',
  durationSeconds: 1800,
);

typedef _WaterLoader =
    Future<List<AlertInfo>> Function({required bool history});

typedef _MonitoringLoader =
    Future<MonitoringIncidentPage> Function({
      required bool history,
      required int page,
      required int pageSize,
    });

typedef _ResolveLoader = Future<AlertInfo> Function(String alertId);

class _ScriptedAlertRepository extends MockAlertRepository {
  _ScriptedAlertRepository({
    this.waterLoader,
    this.monitoringLoader,
    this.resolveLoader,
  });

  final _WaterLoader? waterLoader;
  final _MonitoringLoader? monitoringLoader;
  final _ResolveLoader? resolveLoader;

  @override
  Future<List<AlertInfo>> loadWaterQualityAlerts({
    required SensorSnapshot snapshot,
    required bool history,
  }) =>
      waterLoader?.call(history: history) ??
      super.loadWaterQualityAlerts(snapshot: snapshot, history: history);

  @override
  Future<MonitoringIncidentPage> loadMonitoringIncidents({
    required SensorSnapshot snapshot,
    required bool history,
    required int page,
    int pageSize = 25,
  }) =>
      monitoringLoader?.call(
        history: history,
        page: page,
        pageSize: pageSize,
      ) ??
      super.loadMonitoringIncidents(
        snapshot: snapshot,
        history: history,
        page: page,
        pageSize: pageSize,
      );

  @override
  Future<AlertInfo> resolveAlert(String alertId) =>
      resolveLoader?.call(alertId) ?? super.resolveAlert(alertId);
}

const _staff = AuthUser(
  id: 'staff-11',
  name: 'Staff User',
  email: 'staff@example.test',
  role: UserRole.staff,
);

class _LinkedAlertRepository extends MockAlertRepository {
  bool handled = false;
  int resolveCalls = 0;
  final lookupIds = <String>[];

  AlertInfo get _currentAlert => handled ? _handledAlert : _activeAlert;

  @override
  Future<List<AlertInfo>> loadWaterQualityAlerts({
    required SensorSnapshot snapshot,
    required bool history,
  }) async => history
      ? (handled ? [_handledAlert] : const [])
      : (handled ? const [] : [_activeAlert]);

  @override
  Future<AlertInfo?> findWaterQualityAlert({
    required SensorSnapshot snapshot,
    required String alertId,
  }) async {
    lookupIds.add(alertId);
    return alertId == _activeAlert.id ? _currentAlert : null;
  }

  @override
  Future<AlertInfo> resolveAlert(String alertId) async {
    resolveCalls++;
    handled = true;
    return _handledAlert;
  }
}

class _LinkedHomeRepository extends HomeRepository {
  _LinkedHomeRepository(this.alertRepository);

  final _LinkedAlertRepository alertRepository;
  int loads = 0;

  @override
  bool get isLiveData => true;

  @override
  Future<HomeDashboardData> load() async {
    loads++;
    return HomeDashboardData(
      tanks: const [
        HomeTankSummary(
          id: '8',
          initial: 'B',
          name: 'Backend Tank Eight',
          subtitle: 'North room',
          status: HomeOperationalStatus.critical,
          lastReportLabel: 'Updated just now',
          contextLabel: 'North room',
        ),
      ],
      attentionItems: alertRepository.handled
          ? const []
          : const [
              HomeAttentionItem(
                id: 'water-alert-901',
                tankId: '8',
                tankName: 'Backend Tank Eight',
                type: HomeAttentionType.waterQuality,
                status: HomeOperationalStatus.critical,
                title: 'Critical pH condition',
                message: 'Backend alert record 901',
                actionLabel: 'View alert',
                sourceId: '901',
              ),
            ],
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
}

class _LinkedTankRepository implements TankRepository {
  _LinkedTankRepository(this.alertRepository);

  final _LinkedAlertRepository alertRepository;
  int detailLoads = 0;

  @override
  bool get isLiveData => true;

  @override
  Future<List<TankInfo>> loadTanks({required SensorSnapshot snapshot}) async =>
      [_tank()];

  @override
  Future<TankInfo> loadTankDetail(
    String tankId, {
    required SensorSnapshot snapshot,
  }) async {
    detailLoads++;
    return _tank(
      issues: alertRepository.handled
          ? const []
          : const [
              TankIssue(
                id: 'water-alert-901',
                category: TankIssueCategory.waterQuality,
                severity: TankIssueSeverity.critical,
                title: 'Critical pH reading',
                message: 'Backend alert record 901',
                timeLabel: 'Started Sep 25',
                lifecycle: TankIssueLifecycle.active,
                sourceId: '901',
              ),
            ],
    );
  }

  TankInfo _tank({List<TankIssue> issues = const []}) => TankInfo(
    id: '8',
    initial: 'B',
    name: 'Backend Tank Eight',
    subtitle: 'Freshwater · 100 L',
    status: 'critical',
    typeLabel: 'Freshwater',
    volumeLabel: '100 L',
    lastFedLabel: '',
    description: 'Live test tank',
    locationLabel: 'North room',
    lastReportLabel: 'Updated just now',
    latestCondition: 'Backend status requires attention.',
    monitoringLabel: 'Reporting normally',
    lifecycle: TankLifecycle.active,
    issues: issues,
    isLiveData: true,
    assignedSpeciesCount: 0,
  );
}

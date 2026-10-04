import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:aqualogic/app/theme/app_colors.dart';
import 'package:aqualogic/features/alerts/data/mock_alert_repository.dart';
import 'package:aqualogic/features/alerts/models/alert_context.dart';
import 'package:aqualogic/features/alerts/models/alert_info.dart';
import 'package:aqualogic/features/alerts/screens/alert_detail_screen.dart';
import 'package:aqualogic/features/sensors/data/mock_sensor_feed.dart';
import 'package:aqualogic/features/sensors/models/sensor_snapshot.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

const alert = AlertInfo(
  id: '41',
  tankId: '2',
  tankName: 'Tank Two',
  parameter: 'Temperature',
  severity: AlertSeverity.warning,
  message: 'Temperature is outside its warning threshold',
  startedLabel: 'Created today',
  lifecycle: AlertLifecycle.active,
  icon: LucideIcons.triangleAlert,
);

class ContextRepository extends MockAlertRepository {
  bool fail = false;
  AlertSpeciesContext? species;
  bool retired = false;
  bool handled = false;
  int loads = 0;
  Completer<void>? pending;
  @override
  bool get isLiveData => true;
  @override
  Future<AlertContext> loadAlertContext({
    required String alertId,
    required SensorSnapshot snapshot,
  }) async {
    loads++;
    await pending?.future;
    if (fail) throw StateError('Context unavailable');
    return AlertContext(
      alert: handled
          ? alert.copyWith(
              lifecycle: AlertLifecycle.handled,
              resolutionSource: AlertResolutionSource.operator,
            )
          : alert,
      speciesContext: species,
      tankLifecycle: retired ? 'retired' : 'active',
      evaluatedAt: DateTime.utc(2026, 10, 2),
      linkedReading: AlertContextReading(
        id: 10,
        value: 29,
        unit: '°C',
        observedAt: DateTime.utc(2026, 10, 1),
        receivedAt: DateTime.utc(2026, 10, 1, 23, 59),
        reportingFreshness: 'fresh',
      ),
      latestReading: AlertContextReading(
        id: 11,
        value: 25,
        unit: '°C',
        observedAt: DateTime.utc(2026, 9, 30),
        receivedAt: DateTime.utc(2026, 10, 2),
        reportingFreshness: 'fresh',
      ),
      linkedThreshold: const AlertContextThreshold(
        unit: '°C',
        warningMin: 20,
        warningMax: 28,
        criticalMin: 18,
        criticalMax: 30,
        enabled: true,
        source: 'global',
      ),
      currentThreshold: const AlertContextThreshold(
        unit: '°C',
        warningMin: 20,
        warningMax: 28,
        criticalMin: 18,
        criticalMax: 30,
        enabled: false,
        source: 'tank',
      ),
      code: 'temperature.above.v1',
      direction: 'above',
      explanation:
          'The linked temperature reading is above an associated configured bound.',
      checks: const [
        'Confirm the measurement.',
        'Inspect the heater if installed.',
        'Review lighting duration.',
        'Verify circulation.',
      ],
      advisory:
          'These checks are advisory. Handling does not confirm water recovery.',
    );
  }

  @override
  Future<AlertInfo> resolveAlert(String alertId) async {
    handled = true;
    return alert.copyWith(
      lifecycle: AlertLifecycle.handled,
      resolutionSource: AlertResolutionSource.operator,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (Platform.environment['AQUALOGIC_DETAIL_CAPTURE'] == null) return;
    final text = FontLoader('Geist');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      text.addFont(rootBundle.load('assets/fonts/Geist-$weight.ttf'));
    }
    await text.load();
    final icons = FontLoader('packages/lucide_icons_flutter/Lucide')
      ..addFont(
        rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
      );
    await icons.load();
  });

  testWidgets(
    'current species context expands individual stored preferences at narrow width',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = ContextRepository()
        ..species = AlertSpeciesContext(
          parameter: 'temperature',
          status: 'unavailable',
          reason: 'stale_observation',
          unit: '°C',
          readingId: 11,
          observedAt: DateTime.utc(2026, 10, 1),
          receivedAt: DateTime.utc(2026, 10, 2),
          counts: const {
            'assigned': 1,
            'evaluable': 0,
            'within': 0,
            'outside': 0,
            'unavailable': 1,
          },
          species: const [
            AlertSpeciesPreference(
              id: 1,
              name: 'Fictional preference',
              minimum: 20,
              maximum: null,
              result: 'unavailable',
              reason: 'stale_observation',
            ),
          ],
          advisory:
              "Stored species preferences provide additional context. AquaLogic alerts continue to use the tank's configured thresholds.",
        );
      await tester.pumpWidget(
        MaterialApp(
          home: AlertDetailScreen(
            alert: alert,
            snapshot: MockSensorFeed.snapshot(0),
            repository: repository,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('View individual stored preferences'),
        150,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('View individual stored preferences'));
      await tester.pumpAndSettle();
      expect(find.text('Fictional preference'), findsOneWidget);
      expect(
        find.textContaining('1 distinct species assigned'),
        findsOneWidget,
      );
      expect(find.textContaining('No upper bound'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'context keeps summary during loading, retries without invented guidance, and handles authoritatively',
    (tester) async {
      final repository = ContextRepository()..pending = Completer<void>();
      final resolved = <AlertInfo>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            fontFamily: 'Geist',
            colorScheme: ColorScheme.fromSeed(seedColor: AppColors.teal)
                .copyWith(
                  primary: AppColors.tealDark,
                  onPrimary: Colors.white,
                  surface: Colors.white,
                  onSurface: AppColors.text,
                  outline: AppColors.line,
                ),
          ),
          home: AlertDetailScreen(
            alert: alert,
            snapshot: MockSensorFeed.snapshot(0),
            repository: repository,
            onAlertResolved: resolved.add,
          ),
        ),
      );
      expect(find.text(alert.message), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      repository.fail = true;
      repository.pending!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Alert context could not be loaded.'), findsOneWidget);
      expect(find.text('Suggested checks'), findsNothing);
      repository.fail = false;
      repository.pending = null;
      await tester.tap(find.text('Retry context'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('alert-detail-mark-handled')),
        200,
      );
      await tester.tap(find.byKey(const ValueKey('alert-detail-mark-handled')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Mark handled'),
        ),
      );
      await tester.pumpAndSettle();
      expect(repository.handled, isTrue);
      expect(repository.loads, 3);
      expect(resolved, hasLength(1));
      expect(
        find.byKey(const ValueKey('alert-detail-mark-handled')),
        findsNothing,
      );
    },
  );

  testWidgets(
    '320px detail remains scrollable and exposes contextual navigation and checks',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = ContextRepository();
      final navigation = <String>[];
      final boundary = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            fontFamily: 'Geist',
            colorScheme: ColorScheme.fromSeed(seedColor: AppColors.teal)
                .copyWith(
                  primary: AppColors.tealDark,
                  onPrimary: Colors.white,
                  surface: Colors.white,
                  onSurface: AppColors.text,
                  outline: AppColors.line,
                ),
          ),
          home: RepaintBoundary(
            key: boundary,
            child: AlertDetailScreen(
              alert: alert,
              snapshot: MockSensorFeed.snapshot(0),
              repository: repository,
              onOpenTank: (id) => navigation.add('tank:$id'),
              onOpenEquipment: (id) => navigation.add('equipment:$id'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() => capture(boundary, 'mobile-top'));
      await tester.scrollUntilVisible(find.text('Suggested checks'), 200);
      expect(
        find.textContaining('Recent receipt does not prove'),
        findsOneWidget,
      );
      expect(find.textContaining('Currently disabled'), findsOneWidget);
      await tester.pumpAndSettle();
      await tester.runAsync(() => capture(boundary, 'mobile-checks'));
      await tester.scrollUntilVisible(find.text('View equipment'), 200);
      await tester.tap(find.text('View equipment'));
      await tester.tap(find.text('View tank'));
      expect(navigation, ['equipment:2', 'tank:2']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'retired context disables handling and equipment while retaining history',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            fontFamily: 'Geist',
            colorScheme: ColorScheme.fromSeed(seedColor: AppColors.teal)
                .copyWith(
                  primary: AppColors.tealDark,
                  onPrimary: Colors.white,
                  surface: Colors.white,
                  onSurface: AppColors.text,
                  outline: AppColors.line,
                ),
          ),
          home: AlertDetailScreen(
            alert: alert,
            snapshot: MockSensorFeed.snapshot(0),
            repository: ContextRepository()..retired = true,
            onOpenEquipment: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Suggested checks'), 200);
      expect(find.text('View equipment'), findsNothing);
      expect(
        find.byKey(const ValueKey('alert-detail-mark-handled')),
        findsNothing,
      );
      expect(find.text('Suggested checks'), findsOneWidget);
    },
  );
}

Future<void> capture(GlobalKey key, String name) async {
  final directory = Platform.environment['AQUALOGIC_DETAIL_CAPTURE'];
  if (directory == null) return;
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage();
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  await File('$directory/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
  image.dispose();
}

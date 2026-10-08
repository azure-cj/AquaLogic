import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:aqualogic/features/console/controllers/console_controller.dart';
import 'package:aqualogic/features/console/data/console_repository.dart';
import 'package:aqualogic/features/console/data/esp32_console_repository.dart';
import 'package:aqualogic/features/console/data/mock_console_repository.dart';
import 'package:aqualogic/features/console/models/console_command.dart';
import 'package:aqualogic/features/console/platform/console_display_session.dart';
import 'package:aqualogic/features/console/screens/tank_console_screen.dart';
import 'package:aqualogic/features/console/widgets/console_connection_indicator.dart';
import 'package:aqualogic/features/console/widgets/console_equipment_card.dart';
import 'package:aqualogic/features/auth/models/auth_user.dart';
import 'package:aqualogic/features/auth/models/user_role.dart';
import 'package:aqualogic/features/more/screens/more_screen.dart';
import 'package:aqualogic/features/sensors/data/mock_sensor_feed.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Display implements ConsoleDisplaySession {
  int enters = 0;
  int exits = 0;
  @override
  Future<void> enter() async {
    enters++;
  }

  @override
  Future<void> exit() async {
    exits++;
  }
}

void main() {
  test(
    'mock command IDs track sending confirming confirmed without optimistic state',
    () async {
      final repository = MockConsoleRepository();
      addTearDown(() {
        unawaited(repository.dispose());
      });
      final command = await repository.setLight(false);
      expect(command.status, ConsoleCommandStatus.sending);
      expect((await repository.getState()).equipment.lightOn, isTrue);
      final transitions = <ConsoleCommandStatus>[];
      final subscription = repository
          .watchCommand(command.id)
          .listen((value) => transitions.add(value.status));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(const Duration(milliseconds: 450));
      expect(
        (await repository.getCommand(command.id))?.status,
        ConsoleCommandStatus.confirming,
      );
      expect((await repository.getState()).equipment.lightOn, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 1250));
      expect((await repository.getState()).equipment.lightOn, isFalse);
      expect(transitions, [
        ConsoleCommandStatus.sending,
        ConsoleCommandStatus.confirming,
        ConsoleCommandStatus.confirmed,
      ]);
      await subscription.cancel();
    },
  );

  test(
    'cloud offline allows local commands; local offline rejects them',
    () async {
      final repository = MockConsoleRepository();
      addTearDown(() {
        unawaited(repository.dispose());
      });
      await repository.applyScenario(ConsoleScenario.cloudOffline);
      final command = await repository.setUV(false);
      expect(command.status, ConsoleCommandStatus.sending);
      await Future<void>.delayed(const Duration(seconds: 2));
      expect((await repository.getState()).equipment.uvOn, isFalse);
      expect((await repository.getState()).cloudConnected, isFalse);
      await repository.applyScenario(ConsoleScenario.localOffline);
      expect((await repository.feed()).status, ConsoleCommandStatus.rejected);
      await repository.applyScenario(ConsoleScenario.bothOffline);
      expect(
        (await repository.setLight(false)).status,
        ConsoleCommandStatus.rejected,
      );
      await repository.retryLocalConnection();
      expect((await repository.getState()).localConnected, isTrue);
      expect((await repository.getState()).cloudConnected, isFalse);
    },
  );

  test(
    'disconnect mid-command retains unknown outcome and never replays',
    () async {
      final repository = MockConsoleRepository();
      addTearDown(() {
        unawaited(repository.dispose());
      });
      final command = await repository.setLight(false);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await repository.applyScenario(ConsoleScenario.localOffline);
      await Future<void>.delayed(const Duration(seconds: 3));
      expect(
        (await repository.getCommand(command.id))?.status,
        ConsoleCommandStatus.unknown,
      );
      expect((await repository.getState()).equipment.lightOn, isTrue);
      await repository.retryLocalConnection();
      expect(
        (await repository.getCommand(command.id))?.status,
        ConsoleCommandStatus.unknown,
      );
      expect((await repository.getState()).equipment.lightOn, isTrue);
    },
  );

  test(
    'rejected and unknown fixtures do not fabricate equipment success',
    () async {
      final repository = MockConsoleRepository();
      addTearDown(() {
        unawaited(repository.dispose());
      });
      await repository.applyScenario(ConsoleScenario.rejected);
      expect((await repository.feed()).status, ConsoleCommandStatus.rejected);
      expect((await repository.getState()).equipment.feederRunning, isFalse);
      await repository.applyScenario(ConsoleScenario.unknown);
      final command = await repository.setUV(false);
      await Future<void>.delayed(const Duration(seconds: 2));
      expect(
        (await repository.getCommand(command.id))?.status,
        ConsoleCommandStatus.unknown,
      );
      expect((await repository.getState()).equipment.uvOn, isTrue);
      expect((await repository.getState()).equipment.uvConfirmed, isFalse);
      final otherCommand = await repository.setLight(false);
      expect(otherCommand.status, ConsoleCommandStatus.sending);
      await Future<void>.delayed(const Duration(seconds: 2));
      expect((await repository.getState()).equipment.uvConfirmed, isFalse);
      expect(
        (await repository.setUV(false)).status,
        ConsoleCommandStatus.rejected,
      );
      await repository.applyScenario(ConsoleScenario.normal);
      expect((await repository.getState()).equipment.uvConfirmed, isTrue);
    },
  );

  test(
    'concurrent submission is rejected without replacing active command',
    () async {
      final repository = MockConsoleRepository();
      addTearDown(() {
        unawaited(repository.dispose());
      });
      final first = await repository.feed();
      expect((await repository.feed()).status, ConsoleCommandStatus.rejected);
      expect((await repository.getState()).command?.id, first.id);
      await Future<void>.delayed(const Duration(seconds: 2));
      expect(
        (await repository.getCommand(first.id))?.status,
        ConsoleCommandStatus.confirmed,
      );
    },
  );

  test('ESP32 adapter remains read only without configuration', () async {
    final repository = Esp32ConsoleRepository();
    expect(repository.prototypeControls, isNull);
    expect((await repository.getState()).isSimulated, isFalse);
    expect((await repository.getState()).temperature, isNull);
    expect((await repository.feed()).status, ConsoleCommandStatus.rejected);
    await repository.dispose();
  });

  test(
    'controller prevents duplicate taps and follows repository state',
    () async {
      final repository = MockConsoleRepository();
      final controller = ConsoleController(repository)..start();
      await Future<void>.delayed(Duration.zero);
      final first = controller.submit(ConsoleAction.lightOff);
      expect(await controller.submit(ConsoleAction.lightOff), isNull);
      final command = await first;
      await Future<void>.delayed(const Duration(seconds: 2));
      expect(controller.state?.command?.id, command?.id);
      expect(controller.state?.command?.status, ConsoleCommandStatus.confirmed);
      expect(controller.state?.equipment.lightOn, isFalse);
      controller.dispose();
      await repository.dispose();
    },
  );

  for (final size in [
    const Size(844, 390),
    const Size(740, 360),
    const Size(640, 320),
    const Size(390, 844),
  ]) {
    testWidgets('console fits ${size.width} x ${size.height}', (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = MockConsoleRepository();
      final display = _Display();
      await tester.pumpWidget(
        MaterialApp(
          home: TankConsoleScreen(
            repository: repository,
            displaySession: display,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('27.3', findRichText: true),
        findsNothing,
      ); // Units share a rich value line.
      expect(find.textContaining('27.3', findRichText: true), findsOneWidget);
      expect(find.text('7.32', findRichText: true), findsOneWidget);
      expect(find.text('Simulated data'), findsOneWidget);
      expect(find.text('Pump A'), findsOneWidget);
      expect(display.enters, 1);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(display.exits, 1);
      await repository.dispose();
    });
  }

  testWidgets('controls show live-style progress and simulated pump controls', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(844, 390));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = MockConsoleRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: TankConsoleScreen(
          repository: repository,
          displaySession: _Display(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('console-light')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Turn off'));
    await tester.pump();
    expect(find.textContaining('SENDING'), findsWidgets);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('CONFIRMING'), findsWidgets);
    await tester.pump(const Duration(milliseconds: 1300));
    expect(find.textContaining('CONFIRMED'), findsWidgets);
    await tester.tap(find.byTooltip('Close controls'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('console-pump-a')));
    await tester.pumpAndSettle();
    expect(find.text('Prototype · simulated data'), findsOneWidget);
    expect(find.text('Dispense 1.00 mL'), findsOneWidget);
    expect(find.text('Stop motor'), findsOneWidget);
    expect(find.text('Retract full stroke'), findsOneWidget);
    expect(find.text('Confirm refill'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await repository.dispose();
  });

  testWidgets(
    'offline disables controls, retains metrics and retry preserves cloud status',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(844, 390));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = MockConsoleRepository();
      await repository.applyScenario(ConsoleScenario.bothOffline);
      await tester.pumpWidget(
        MaterialApp(
          home: TankConsoleScreen(
            repository: repository,
            displaySession: _Display(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ConsoleEquipmentCard>(
              find.byKey(const ValueKey('console-feeder')),
            )
            .onTap,
        isNull,
      );
      expect(find.text('Last known'), findsNWidgets(4));
      expect(find.text('Local device offline'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(
        tester
            .widget<ConsoleEquipmentCard>(
              find.byKey(const ValueKey('console-feeder')),
            )
            .onTap,
        isNotNull,
      );
      expect(
        tester
            .widget<ConsoleConnectionIndicator>(
              find.widgetWithText(ConsoleConnectionIndicator, 'Cloud'),
            )
            .connected,
        isFalse,
      );
      await tester.pumpWidget(const SizedBox());
      await repository.dispose();
    },
  );

  testWidgets(
    'More opens console and deliberate exit returns to introduction',
    (tester) async {
      const displayChannel = MethodChannel(
        'com.aqualogic.mobile/console_display',
      );
      final displayCalls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        displayChannel,
        (call) async {
          displayCalls.add(call.method);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          displayChannel,
          null,
        ),
      );
      await tester.binding.setSurfaceSize(const Size(844, 390));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: MoreScreen(
            snapshot: MockSensorFeed.snapshot(0),
            user: const AuthUser(
              id: 'owner',
              name: 'Owner',
              email: 'owner@aqualogic.local',
              role: UserRole.admin,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('more-tank-console')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const ValueKey('more-tank-console')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('enter-console')));
      await tester.tap(find.byKey(const ValueKey('enter-console')));
      await tester.pumpAndSettle();
      expect(find.byType(TankConsoleScreen), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('console-settings')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Exit Console Mode'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Exit Console Mode'));
      await tester.pumpAndSettle();
      expect(find.text('Exit Console Mode?'), findsOneWidget);
      await tester.tap(find.text('Stay in console'));
      await tester.pumpAndSettle();
      expect(find.byType(TankConsoleScreen), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Exit console'));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(displayCalls, containsAllInOrder(['enter', 'exit']));
      expect(find.byKey(const ValueKey('enter-console')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'large text landscape remains readable without layout exceptions',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(740, 360));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = MockConsoleRepository();
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: TankConsoleScreen(
            repository: repository,
            displaySession: _Display(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await repository.dispose();
    },
  );

  if (Platform.environment['CONSOLE_CAPTURE'] == '1') {
    for (final scenario in [
      ConsoleScenario.normal,
      ConsoleScenario.attention,
      ConsoleScenario.cloudOffline,
      ConsoleScenario.localOffline,
    ]) {
      testWidgets('capture ${scenario.name}', (tester) async {
        await tester.binding.setSurfaceSize(const Size(844, 390));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final repository = MockConsoleRepository();
        await repository.applyScenario(scenario);
        await tester.runAsync(() async {
          final loader = FontLoader('Geist')
            ..addFont(rootBundle.load('assets/fonts/Geist-Regular.ttf'));
          await loader.load();
          final icons = FontLoader('MaterialIcons')
            ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
          await icons.load();
        });
        final key = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(fontFamily: 'Geist'),
              home: TankConsoleScreen(
                repository: repository,
                displaySession: _Display(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 2);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          final directory = Directory('build/console-preview')
            ..createSync(recursive: true);
          File(
            '${directory.path}/${scenario.name}.png',
          ).writeAsBytesSync(data!.buffer.asUint8List());
          image.dispose();
        });
        await tester.pumpWidget(const SizedBox());
        await repository.dispose();
      });
    }
  }
}

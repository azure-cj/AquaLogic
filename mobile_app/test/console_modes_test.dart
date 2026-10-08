import 'package:aqualogic/features/console/data/esp32_console_parser.dart';
import 'package:aqualogic/features/console/data/mock_console_repository.dart';
import 'package:aqualogic/features/console/models/console_command.dart';
import 'package:aqualogic/features/console/platform/console_display_session.dart';
import 'package:aqualogic/features/console/screens/tank_console_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Display implements ConsoleDisplaySession {
  @override
  Future<void> enter() async {}
  @override
  Future<void> exit() async {}
}

const _lock = ValueKey('console-lock');

void main() {
  Future<MockConsoleRepository> open(
    WidgetTester tester, {
    bool locked = true,
    Duration idle = const Duration(seconds: 60),
  }) async {
    await tester.binding.setSurfaceSize(const Size(960, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = MockConsoleRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: TankConsoleScreen(
          repository: repository,
          displaySession: _Display(),
          initiallyLocked: locked,
          idleTimeout: idle,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return repository;
  }

  Future<void> close(WidgetTester tester, MockConsoleRepository repo) async {
    await tester.pumpWidget(const SizedBox());
    await repo.dispose();
  }

  Future<void> hold(WidgetTester tester, Finder target, Duration time) async {
    final gesture = await tester.startGesture(tester.getCenter(target));
    await tester.pump();
    await tester.pump(time);
    await gesture.up();
    await tester.pump();
  }

  testWidgets('locked display shows readings but no controls', (tester) async {
    final repo = await open(tester);
    expect(find.byKey(const ValueKey('console-light')), findsNothing);
    expect(find.byKey(const ValueKey('console-settings')), findsNothing);
    await tester.tapAt(const Offset(480, 300));
    await tester.pump();
    expect(find.text('Hold the lock to use controls'), findsOneWidget);
    expect((await repo.getState()).command, isNull);
    await tester.pump(const Duration(seconds: 3));
    await close(tester, repo);
  });

  testWidgets('a short press does not unlock; a full hold does', (
    tester,
  ) async {
    final repo = await open(tester);
    await hold(tester, find.byKey(_lock), const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('console-light')), findsNothing);
    await hold(tester, find.byKey(_lock), const Duration(milliseconds: 1000));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('console-light')), findsOneWidget);
    // Tapping the chip in Control mode locks again immediately.
    await tester.tap(find.byKey(_lock));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('console-light')), findsNothing);
    await close(tester, repo);
  });

  testWidgets('lighting toggles in one tap without optimistic state', (
    tester,
  ) async {
    final repo = await open(tester, locked: false);
    await tester.tap(find.byKey(const ValueKey('console-light')));
    await tester.pump();
    expect(find.text('Turning off…'), findsOneWidget);
    expect((await repo.getState()).equipment.lightOn, isTrue);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Turning off…'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pumpAndSettle();
    expect((await repo.getState()).equipment.lightOn, isFalse);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('console-light')),
        matching: find.text('Off'),
      ),
      findsOneWidget,
    );
    await close(tester, repo);
  });

  testWidgets('feeder needs a full hold; a tap or early release never feeds', (
    tester,
  ) async {
    final repo = await open(tester, locked: false);
    final feeder = find.byKey(const ValueKey('console-feeder'));
    await tester.tap(feeder);
    await tester.pump();
    expect((await repo.getState()).commands[ConsoleActuator.feeder], isNull);
    await hold(tester, feeder, const Duration(milliseconds: 500));
    expect((await repo.getState()).commands[ConsoleActuator.feeder], isNull);
    await hold(tester, feeder, const Duration(milliseconds: 1100));
    expect(
      (await repo.getState()).commands[ConsoleActuator.feeder]?.action,
      ConsoleAction.feed,
    );
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    await close(tester, repo);
  });

  testWidgets('idle relocks, but never while a command is unconfirmed', (
    tester,
  ) async {
    final repo = await open(
      tester,
      locked: false,
      idle: const Duration(milliseconds: 800),
    );
    await tester.tap(find.byKey(const ValueKey('console-uv')));
    await tester.pump();
    // The timeout passes while the command is still pending: stay unlocked.
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.byKey(const ValueKey('console-uv')), findsOneWidget);
    // Once confirmed, the next idle period relocks.
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('console-uv')), findsNothing);
    await close(tester, repo);
  });

  test('parser reads feeder details and rejects malformed schedules', () {
    final equipment = Esp32ConsoleParser.equipment({
      '/feeder/status': {
        'feeding': false,
        'feed_count': 14,
        'last_fed': '08:30',
        'open_angle': 129,
        'duration_ms': 2000,
        'schedule': [
          {'hour': 8, 'minute': 0, 'enabled': true},
          {'hour': 14, 'minute': 10, 'enabled': true},
          {'hour': 18, 'minute': 0, 'enabled': false},
        ],
      },
      '/syringeA/status': {
        'active': false,
        'last_dispensed': '20:41',
        'next_dose_at': ' ',
        'schedule_event': 'Scheduled dose skipped: cooldown',
      },
    });
    expect(equipment.feedCount, 14);
    expect(equipment.lastFed, '08:30');
    expect(equipment.feederAngle, 129);
    expect(equipment.feederDurationMs, 2000);
    expect(equipment.feederSchedule.map((s) => s.enabled), [true, true, false]);
    expect(equipment.pumpA.lastDispensed, '20:41');
    expect(equipment.pumpA.nextDoseAt, isNull);
    expect(equipment.pumpA.scheduleEvent, contains('cooldown'));

    expect(Esp32ConsoleParser.schedule(null), isEmpty);
    expect(
      Esp32ConsoleParser.schedule([
        {'hour': 8, 'minute': 0, 'enabled': true},
      ]),
      isEmpty,
    );
    expect(
      Esp32ConsoleParser.schedule([
        {'hour': 25, 'minute': 0, 'enabled': true},
        {'hour': 1, 'minute': 0, 'enabled': true},
        {'hour': 2, 'minute': 0, 'enabled': true},
      ]),
      isEmpty,
    );
  });
}

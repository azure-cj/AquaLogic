import 'dart:async';
import 'package:aqualogic/features/console/controllers/console_controller.dart';
import 'package:aqualogic/features/console/data/console_repository.dart';
import 'package:aqualogic/features/console/data/mock_console_repository.dart';
import 'package:aqualogic/features/console/models/console_command.dart';
import 'package:aqualogic/features/console/screens/tank_console_screen.dart';
import 'package:aqualogic/features/console/platform/console_display_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Display implements ConsoleDisplaySession {
  @override
  Future<void> enter() async {}
  @override
  Future<void> exit() async {}
}

void main() {
  for (final action in ConsoleAction.values.where((a) => a.isPump)) {
    testWidgets(
      'simulation supports ${action.name} through live-style stages',
      (tester) async {
        final repository = MockConsoleRepository();
        addTearDown(repository.dispose);
        final command = await repository.pump(action);
        expect(command.status, ConsoleCommandStatus.sending);
        expect(command.id, startsWith('prototype-'));
        expect((await repository.getState()).isSimulated, isTrue);
        await tester.pump(const Duration(milliseconds: 500));
        expect(
          (await repository.getCommand(command.id))!.status,
          ConsoleCommandStatus.confirming,
        );
        final equipment = (await repository.getState()).equipment;
        final pump = action.actuator == ConsoleActuator.pumpA
            ? equipment.pumpA
            : equipment.pumpB;
        expect(pump.active, action.isDispense || action.isRetract);
        expect(pump.remainingMl, action.isDispense ? 4 : 5);
        await tester.pump(const Duration(milliseconds: 1300));
        expect(
          (await repository.getCommand(command.id))!.status,
          ConsoleCommandStatus.confirmed,
        );
        expect(
          (await repository.getCommand(command.id))!.message,
          contains('Simulation'),
        );
        expect((await repository.getState()).equipment.pumpA.active, isFalse);
        expect((await repository.getState()).equipment.pumpB.active, isFalse);
      },
    );
  }

  testWidgets(
    'shared cooldown, mutual exclusion, refill and reset are simulated',
    (tester) async {
      var now = DateTime(2026, 10, 7, 12);
      final repository = MockConsoleRepository(clock: () => now);
      addTearDown(repository.dispose);
      final dose = await repository.pump(ConsoleAction.pumpADispense);
      expect(
        (await repository.pump(ConsoleAction.pumpADispense)).status,
        ConsoleCommandStatus.rejected,
      );
      expect(
        (await repository.pump(ConsoleAction.pumpBDispense)).message,
        contains('busy'),
      );
      await tester.pump(const Duration(seconds: 2));
      expect(
        (await repository.getCommand(dose.id))!.status,
        ConsoleCommandStatus.confirmed,
      );
      expect(
        (await repository.pump(ConsoleAction.pumpBDispense)).message,
        contains('cooldown'),
      );
      await repository.pump(ConsoleAction.pumpARefill);
      await tester.pump(const Duration(seconds: 2));
      expect((await repository.getState()).equipment.pumpA.remainingMl, 5);
      expect(
        (await repository.pump(ConsoleAction.pumpADispense)).message,
        contains('cooldown'),
      );
      now = now.add(const Duration(hours: 2));
      expect(
        (await repository.pump(ConsoleAction.pumpBDispense)).status,
        ConsoleCommandStatus.sending,
      );
      await tester.pump(const Duration(seconds: 2));
      await repository.applyScenario(ConsoleScenario.resetSimulation);
      expect((await repository.getState()).equipment.pumpB.remainingMl, 5);
      expect((await repository.getState()).commands, isEmpty);
      expect(
        (await repository.pump(ConsoleAction.pumpADispense)).status,
        ConsoleCommandStatus.sending,
      );
      repository.cancelCommands();
    },
  );

  testWidgets(
    'Stop interrupts dose; prior outcome remains unknown and is never replayed',
    (tester) async {
      final repository = MockConsoleRepository();
      final controller = ConsoleController(repository)..start();
      addTearDown(() {
        controller.dispose();
        unawaited(repository.dispose());
      });
      await tester.pump();
      final dose = await controller.submit(ConsoleAction.pumpADispense);
      await tester.pump(const Duration(milliseconds: 500));
      expect(controller.canSubmit(ConsoleAction.pumpADispense), isFalse);
      expect(controller.canSubmit(ConsoleAction.pumpBDispense), isFalse);
      expect(controller.canSubmit(ConsoleAction.pumpAStop), isTrue);
      final stop = await controller.submit(ConsoleAction.pumpAStop);
      await tester.pump(const Duration(seconds: 2));
      expect(
        (await repository.getCommand(dose!.id))!.status,
        ConsoleCommandStatus.unknown,
      );
      expect(
        (await repository.getCommand(stop!.id))!.status,
        ConsoleCommandStatus.confirmed,
      );
      expect((await repository.getState()).equipment.pumpA.remainingMl, 4);
      expect(
        (await repository.getState()).uncertainCommands.single.id,
        dose.id,
      );
      await tester.pump(const Duration(seconds: 4));
      expect((await repository.getState()).equipment.pumpA.doseCount, 1);
    },
  );

  testWidgets(
    'unknown and rejected pump scenarios never fabricate a dispense result',
    (tester) async {
      final repository = MockConsoleRepository();
      addTearDown(repository.dispose);
      await repository.applyScenario(ConsoleScenario.rejected);
      expect(
        (await repository.pump(ConsoleAction.pumpADispense)).status,
        ConsoleCommandStatus.rejected,
      );
      await repository.applyScenario(ConsoleScenario.unknown);
      final command = await repository.pump(ConsoleAction.pumpADispense);
      await tester.pump(const Duration(seconds: 2));
      expect(
        (await repository.getCommand(command.id))!.status,
        ConsoleCommandStatus.unknown,
      );
      expect((await repository.getState()).equipment.pumpA.active, isNull);
      expect((await repository.getState()).equipment.pumpAStatus, 'UNKNOWN');
      expect((await repository.getState()).equipment.pumpA.remainingMl, 5);
      await tester.pump(const Duration(seconds: 4));
      expect((await repository.getState()).equipment.pumpA.doseCount, 0);
      await repository.applyScenario(ConsoleScenario.normal);
      expect((await repository.getState()).equipment.pumpA.active, isFalse);
      expect(
        (await repository.getCommand(command.id))!.status,
        ConsoleCommandStatus.unknown,
      );
    },
  );

  testWidgets(
    'cloud offline permits pumps; local offline and leaving cancel without replay',
    (tester) async {
      final repository = MockConsoleRepository();
      final controller = ConsoleController(repository)..start();
      await tester.pump();
      await controller.applyScenario(ConsoleScenario.cloudOffline);
      await tester.pump();
      expect(controller.canSubmit(ConsoleAction.pumpADispense), isTrue);
      final command = await controller.submit(ConsoleAction.pumpADispense);
      await controller.applyScenario(ConsoleScenario.bothOffline);
      await tester.pump();
      expect(controller.canSubmit(ConsoleAction.pumpAStop), isFalse);
      expect(
        (await repository.getCommand(command!.id))!.status,
        ConsoleCommandStatus.unknown,
      );
      await controller.retry();
      expect(controller.state!.cloudConnected, isFalse);
      await tester.pump(const Duration(seconds: 3));
      expect(controller.state!.equipment.pumpA.doseCount, 0);
      await controller.applyScenario(ConsoleScenario.resetSimulation);
      await tester.pump();
      final next = await controller.submit(ConsoleAction.pumpBDispense);
      controller.dispose();
      await tester.pump(const Duration(seconds: 3));
      expect(
        (await repository.getCommand(next!.id))!.status,
        ConsoleCommandStatus.unknown,
      );
      expect((await repository.getState()).equipment.pumpB.doseCount, 0);
      await repository.dispose();
    },
  );

  testWidgets(
    'landscape pump demo requires confirmation and shows the entire process',
    (tester) async {
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
      await tester.tap(find.byKey(const ValueKey('console-pump-a')));
      await tester.pumpAndSettle();
      expect(find.text('Prototype · simulated data'), findsOneWidget);
      expect(
        find.textContaining('no ESP32 or physical dispensing'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Dispense 1.00 mL'));
      await tester.tap(find.text('Dispense 1.00 mL'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('No hardware action will occur.'),
        findsOneWidget,
      );
      expect((await repository.getState()).commands, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dispense 1.00 mL'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await tester.pump();
      expect(
        (await repository.getState()).command!.status,
        ConsoleCommandStatus.sending,
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.textContaining('CONFIRMING'), findsWidgets);
      expect((await repository.getState()).equipment.pumpA.active, isTrue);
      await tester.pump(const Duration(milliseconds: 1300));
      expect(find.textContaining('CONFIRMED'), findsWidgets);
      expect((await repository.getState()).equipment.pumpA.active, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await repository.dispose();
    },
  );
}

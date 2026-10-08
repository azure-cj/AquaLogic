import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aqualogic/features/console/controllers/console_controller.dart';
import 'package:aqualogic/features/console/data/console_configuration_store.dart';
import 'package:aqualogic/features/console/data/console_http_transport.dart';
import 'package:aqualogic/features/console/data/esp32_console_repository.dart';
import 'package:aqualogic/features/console/models/console_command.dart';
import 'package:aqualogic/features/console/widgets/console_pump_sheet.dart';
import 'package:aqualogic/features/console/widgets/console_command_sheet.dart';

const host = '192.168.100.100';

class Store implements ConsoleConfigurationStore {
  @override
  Future<String?> readHost() async => host;
  @override
  Future<void> writeHost(String host) async {}
}

class FirmwareServer {
  FirmwareServer() {
    reports =
        (jsonDecode(
                  File(
                    'test/fixtures/esp32_248c698/responses.json',
                  ).readAsStringSync(),
                )
                as Map<String, dynamic>)
            .map(
              (key, value) =>
                  MapEntry(key, Map<String, dynamic>.from(value as Map)),
            );
    for (final name in ['A', 'B']) {
      reports['/syringe$name/status']!.addAll({
        'active': false,
        'remaining_ml': 5.0,
        'volume_known': true,
        'refill_required': false,
      });
    }
    acks =
        (jsonDecode(
              File(
                'test/fixtures/esp32_248c698/commands.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>);
  }
  late Map<String, Map<String, dynamic>> reports;
  late Map<String, dynamic> acks;
  late HttpServer server;
  late int port;
  final paths = <String>[];
  final requests = <HttpRequest>[];
  final timers = <Timer>[];
  final modes = <String, String>{};
  final statusErrors = <String>{};
  bool closeOnCommand = false;
  int active = 0, maximum = 0;
  Duration commandDelay = Duration.zero;
  Future<void> open() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    port = server.port;
    server.listen((request) async {
      final path = request.uri.path;
      paths.add(path);
      requests.add(request);
      active++;
      maximum = active > maximum ? active : maximum;
      try {
        request.response.headers.contentType = ContentType.json;
        if (reports.containsKey(path)) {
          if (statusErrors.contains(path)) {
            request.response.statusCode = 503;
            request.response.write('{}');
          } else {
            request.response.write(jsonEncode(reports[path]));
          }
        } else {
          final action = ConsoleAction.values
              .where((a) => a.path == path)
              .firstOrNull;
          if (action == null) {
            request.response.statusCode = 404;
            request.response.write('{}');
          } else {
            final mode = modes[path] ?? 'normal';
            if (closeOnCommand) {
              await server.close(force: true);
              return;
            }
            if (mode == 'rejected' ||
                mode == 'cooldown' ||
                mode == 'persistent') {
              request.response.statusCode = mode == 'persistent' ? 503 : 409;
              request.response.write(
                jsonEncode({
                  action.isRefill ? 'refill_confirmed' : 'dispensed': false,
                  'reason': mode == 'cooldown'
                      ? 'Two-hour chemical-dose cooldown until 2026-10-07 12:00:00'
                      : mode == 'persistent'
                      ? 'Could not persist pump safety state; dose not started'
                      : 'A pump is already active',
                  'next_eligible_at': '2026-10-07 12:00:00',
                }),
              );
            } else {
              if (![
                'mismatch',
                'busy-skip',
                'http',
                'redirect',
                'malformed',
                'timeout-no-action',
              ].contains(mode)) {
                apply(action);
              }
              if (mode.startsWith('timeout')) {
                await Future<void>.delayed(const Duration(milliseconds: 3300));
              }
              if (commandDelay != Duration.zero) {
                await Future<void>.delayed(commandDelay);
              }
              if (mode == 'http') request.response.statusCode = 500;
              if (mode == 'redirect') {
                request.response.statusCode = 302;
                request.response.headers.set(
                  HttpHeaders.locationHeader,
                  '/feeder/feed',
                );
              }
              request.response.write(
                mode == 'malformed' ? '{bad' : jsonEncode(acks[path]),
              );
            }
          }
        }
        await request.response.close();
      } catch (_) {
        /* Client cancellation is part of these tests. */
      } finally {
        active--;
      }
    });
  }

  void apply(ConsoleAction action) {
    final report = reports[action.statusPath]!;
    if (action.actuator == ConsoleActuator.light ||
        action.actuator == ConsoleActuator.uv) {
      report['led_on'] =
          action == ConsoleAction.lightOn || action == ConsoleAction.uvOn;
    } else if (action.isRefill) {
      report.addAll({
        'volume_known': true,
        'remaining_ml': 5.0,
        'refill_required': false,
      });
    } else if (action.isStop) {
      report['active'] = false;
    } else {
      final activeKey = action == ConsoleAction.feed ? 'feeding' : 'active';
      report[activeKey] = true;
      if (!action.isRetract) {
        final key = action == ConsoleAction.feed ? 'feed_count' : 'dose_count';
        report[key] = (report[key] as int) + 1;
        if (action.isDispense) {
          report['remaining_ml'] =
              (report['remaining_ml'] as num) - (report['volume_ml'] as num);
        }
      }
      timers.add(
        Timer(
          const Duration(milliseconds: 180),
          () => report[activeKey] = false,
        ),
      );
    }
  }

  Future<void> close() async {
    for (final timer in timers) {
      timer.cancel();
    }
    await server.close(force: true);
  }
}

class Sockets extends HttpOverrides {
  Sockets(this.server);
  final FirmwareServer server;
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)
        ..connectionFactory = (_, _, _) =>
            Socket.startConnect(InternetAddress.loopbackIPv4, server.port);
}

Future<void> until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 9));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for firmware-shaped state');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FirmwareServer server;
  late Esp32ConsoleRepository repository;
  late ConsoleController controller;
  setUp(() async {
    server = FirmwareServer();
    await server.open();
    repository = Esp32ConsoleRepository(
      configurationStore: Store(),
      pollInterval: const Duration(milliseconds: 70),
    );
    controller = ConsoleController(repository);
  });
  tearDown(() async {
    controller.dispose();
    await repository.dispose();
    await server.close();
  });
  Future<void> run(Future<void> Function() test) =>
      HttpOverrides.runWithHttpOverrides(() async {
        controller.start();
        expect(await repository.testConnection(), isTrue);
        await until(() => controller.state?.localConnected == true);
        await test();
      }, Sockets(server));
  Future<ConsoleCommand> submit(ConsoleAction action) async {
    final command = await controller.submit(action);
    expect(command, isNotNull);
    return command!;
  }

  Future<ConsoleCommand> result(ConsoleCommand command) async {
    await until(
      () =>
          controller.state?.commands[command.action.actuator]?.id ==
              command.id &&
          (controller.state?.commands[command.action.actuator]?.status ==
                  ConsoleCommandStatus.confirmed ||
              controller.state?.commands[command.action.actuator]?.status ==
                  ConsoleCommandStatus.rejected ||
              controller.state?.commands[command.action.actuator]?.status ==
                  ConsoleCommandStatus.unknown ||
              controller.state?.commands[command.action.actuator]?.status ==
                  ConsoleCommandStatus.failed),
    );
    return (await repository.getCommand(command.id))!;
  }

  for (final action in ConsoleAction.values) {
    test(
      '${action.name}: real HTTP request then firmware status confirmation',
      () => run(() async {
        if (action.isStop) {
          server.reports[action.statusPath]!['active'] = true;
          await controller.retry();
        }
        final transitions = <ConsoleCommandStatus>[];
        final subscription = repository.watchState().listen((state) {
          final command = state.commands[action.actuator];
          if (command != null) transitions.add(command.status);
        });
        try {
          final command = await submit(action);
          expect(command.status, ConsoleCommandStatus.sending);
          expect(
            (await result(command)).status,
            ConsoleCommandStatus.confirmed,
          );
          expect(transitions, contains(ConsoleCommandStatus.confirming));
          expect(server.paths.where((p) => p == action.path).length, 1);
          expect(
            server.paths.lastIndexOf(action.statusPath),
            greaterThan(server.paths.indexOf(action.path)),
          );
          for (final request in server.requests) {
            expect(request.method, 'GET');
            expect(
              request.headers.value(HttpHeaders.authorizationHeader),
              isNull,
            );
            expect(request.headers.value(HttpHeaders.cookieHeader), isNull);
          }
          expect(controller.state!.cloudConnected, isNull);
        } finally {
          await subscription.cancel();
        }
      }),
    );
  }
  test(
    'UV unusual led_on and led acknowledgement never contaminate lighting',
    () => run(() async {
      final light = server.reports['/led/status']!['led_on'];
      expect(
        (await result(await submit(ConsoleAction.uvOn))).status,
        ConsoleCommandStatus.confirmed,
      );
      expect(controller.state!.equipment.uvOn, isTrue);
      expect(controller.state!.equipment.lightOn, light);
      expect(
        (await result(await submit(ConsoleAction.uvOff))).status,
        ConsoleCommandStatus.confirmed,
      );
      expect(controller.state!.equipment.lightOn, light);
    }),
  );
  for (final action in [ConsoleAction.lightOff, ConsoleAction.uvOn]) {
    test(
      '${action.name} mismatch stays unknown; later poll confirms actual state; external changes win',
      () => run(() async {
        server.modes[action.path] = 'mismatch';
        final command = await submit(action);
        expect((await result(command)).status, ConsoleCommandStatus.unknown);
        server.apply(action);
        await until(
          () =>
              controller.state!.commands[action.actuator]?.status ==
              ConsoleCommandStatus.confirmed,
        );
        server.reports[action.statusPath]!['led_on'] =
            action == ConsoleAction.lightOff;
        await controller.retry();
        await until(
          () =>
              (action.actuator == ConsoleActuator.light
                  ? controller.state!.equipment.lightOn
                  : controller.state!.equipment.uvOn) ==
              (action == ConsoleAction.lightOff),
        );
        final on = action.actuator == ConsoleActuator.light
            ? controller.state!.equipment.lightOn
            : controller.state!.equipment.uvOn;
        expect(on, action == ConsoleAction.lightOff);
        expect(server.paths.where((p) => p == action.path).length, 1);
      }),
    );
  }
  for (final action in [
    ConsoleAction.lightOff,
    ConsoleAction.uvOn,
    ConsoleAction.feed,
    ConsoleAction.pumpADispense,
    ConsoleAction.pumpBDispense,
  ]) {
    test(
      '${action.name} timeout unknown, no retry, later reports recover',
      () => run(() async {
        server.modes[action.path] = 'timeout';
        final statuses = <ConsoleCommandStatus>[];
        final sub = repository.watchState().listen((s) {
          final c = s.commands[action.actuator];
          if (c != null) statuses.add(c.status);
        });
        try {
          final command = await submit(action);
          await until(() => statuses.contains(ConsoleCommandStatus.unknown));
          await until(
            () =>
                controller.state!.commands[action.actuator]?.status ==
                ConsoleCommandStatus.confirmed,
          );
          expect(
            (await repository.getCommand(command.id))!.message,
            contains(
              action.isPump || action == ConsoleAction.feed
                  ? 'unverified'
                  : 'reports',
            ),
          );
          expect(server.paths.where((p) => p == action.path).length, 1);
        } finally {
          await sub.cancel();
        }
      }),
    );
  }
  for (final mode in ['http', 'malformed', 'redirect']) {
    test(
      'command $mode is uncertain, never replayed, status still authoritative',
      () => run(() async {
        server.modes['/led/off'] = mode;
        final command = await submit(ConsoleAction.lightOff);
        expect((await result(command)).status, ConsoleCommandStatus.unknown);
        await controller.retry();
        expect(controller.state!.equipment.lightOn, isTrue);
        expect(server.paths.where((p) => p == '/led/off').length, 1);
        expect(server.paths, isNot(contains('/feeder/feed')));
      }),
    );
  }
  test(
    'feeder fed:true busy skip never proves feeding; next observed cycle is qualified',
    () => run(() async {
      server.modes['/feeder/feed'] = 'busy-skip';
      final command = await submit(ConsoleAction.feed);
      await until(() => server.paths.contains('/feeder/feed'));
      await controller.retry();
      expect(
        (await repository.getCommand(command.id))!.status,
        ConsoleCommandStatus.confirming,
      );
      expect(controller.state!.equipment.feederRunning, isFalse);
      server.apply(ConsoleAction.feed);
      await until(
        () =>
            controller.state!.commands[ConsoleActuator.feeder]?.status ==
            ConsoleCommandStatus.confirmed,
      );
      expect(
        (await repository.getCommand(command.id))!.message,
        contains('attribution are unverified'),
      );
      expect(server.paths.where((p) => p == '/feeder/feed').length, 1);
    }),
  );
  test(
    'busy feeder blocked without request; repeated taps blocked synchronously',
    () => run(() async {
      server.reports['/feeder/status']!['feeding'] = true;
      await controller.retry();
      expect(
        (await result(await submit(ConsoleAction.feed))).status,
        ConsoleCommandStatus.rejected,
      );
      expect(server.paths, isNot(contains('/feeder/feed')));
      server.reports['/feeder/status']!['feeding'] = false;
      await controller.retry();
      final first = controller.submit(ConsoleAction.feed);
      expect(await controller.submit(ConsoleAction.feed), isNull);
      await result((await first)!);
      expect(server.paths.where((p) => p == '/feeder/feed').length, 1);
    }),
  );
  for (final side in ['A', 'B']) {
    final action = side == 'A'
        ? ConsoleAction.pumpADispense
        : ConsoleAction.pumpBDispense;
    for (final mode in ['rejected', 'cooldown', 'persistent']) {
      test(
        'pump $side preserves firmware $mode rejection and no retry',
        () => run(() async {
          server.modes[action.path] = mode;
          final command = await submit(action);
          final outcome = await result(command);
          expect(outcome.status, ConsoleCommandStatus.rejected);
          expect(
            outcome.message,
            contains(
              mode == 'cooldown'
                  ? 'Two-hour'
                  : mode == 'persistent'
                  ? 'persist'
                  : 'active',
            ),
          );
          await controller.retry();
          expect(server.paths.where((p) => p == action.path).length, 1);
        }),
      );
    }
    for (final volume in [-1, 0, 6, null, '1']) {
      test(
        'pump $side invalid reported volume $volume never sends',
        () => run(() async {
          server.reports[action.statusPath]!['volume_ml'] = volume;
          await controller.retry();
          expect(
            (await result(await submit(action))).status,
            ConsoleCommandStatus.rejected,
          );
          expect(server.paths, isNot(contains(action.path)));
        }),
      );
    }
    test(
      'pump $side missing status, refill required and mutual exclusion block motion',
      () => run(() async {
        final report = server.reports[action.statusPath]!;
        report['active'] = null;
        await controller.retry();
        expect(
          (await result(await submit(action))).status,
          ConsoleCommandStatus.rejected,
        );
        report['active'] = false;
        report['volume_known'] = false;
        await controller.retry();
        expect(
          (await result(await submit(action))).status,
          ConsoleCommandStatus.rejected,
        );
        report['volume_known'] = true;
        server.reports[side == 'A'
                ? '/syringeB/status'
                : '/syringeA/status']!['active'] =
            true;
        await controller.retry();
        expect(
          (await result(await submit(action))).status,
          ConsoleCommandStatus.rejected,
        );
        expect(server.paths, isNot(contains(action.path)));
      }),
    );
  }
  test(
    'shared pump pending gate but telemetry and lighting continue',
    () => run(() async {
      server.commandDelay = const Duration(milliseconds: 250);
      final before = server.paths.where((p) => p == '/data').length;
      final command = await submit(ConsoleAction.pumpADispense);
      expect(await controller.submit(ConsoleAction.pumpBDispense), isNull);
      await until(
        () => server.paths.where((p) => p == '/data').length > before,
      );
      expect(controller.canSubmit(ConsoleAction.lightOff), isTrue);
      await result(command);
      expect(server.paths, isNot(contains('/syringeB/dispense')));
      expect(server.maximum, 1);
    }),
  );
  for (final side in ['A', 'B']) {
    final refill = side == 'A'
        ? ConsoleAction.pumpARefill
        : ConsoleAction.pumpBRefill;
    test(
      'pump $side refill persistence/busy refusal is preserved',
      () => run(() async {
        server.modes[refill.path] = 'persistent';
        final outcome = await result(await submit(refill));
        expect(outcome.status, ConsoleCommandStatus.rejected);
        expect(outcome.message, contains('persist'));
        expect(server.paths.where((p) => p == refill.path).length, 1);
      }),
    );
  }
  test(
    'Stop remains available during pump confirmation; prior outcome stays visible',
    () => run(() async {
      server.timers.clear();
      final dose = await submit(ConsoleAction.pumpADispense);
      await until(() => controller.state!.equipment.pumpA.active == true);
      expect(controller.canSubmit(ConsoleAction.pumpAStop), isTrue);
      final stop = await submit(ConsoleAction.pumpAStop);
      expect((await result(stop)).status, ConsoleCommandStatus.confirmed);
      expect(
        (await repository.getCommand(dose.id))!.status,
        ConsoleCommandStatus.unknown,
      );
      expect(
        controller.state!.uncertainCommands.map((c) => c.id),
        contains(dose.id),
      );
      expect(server.paths.where((p) => p == '/syringeA/dispense').length, 1);
    }),
  );
  test(
    'read-only transport cannot issue command routes through get',
    () => run(() async {
      final transport = createConsoleHttpTransport();
      addTearDown(transport.close);
      for (final action in ConsoleAction.values) {
        await expectLater(
          transport.get(Uri.parse('http://$host${action.path}')),
          throwsFormatException,
        );
      }
      expect(
        server.paths.where((p) => ConsoleAction.values.any((a) => a.path == p)),
        isEmpty,
      );
    }),
  );
  test(
    'unknown non-idempotent outcome expires confirmation, preserves recovered idle, never retries',
    () async {
      await repository.dispose();
      repository = Esp32ConsoleRepository(
        configurationStore: Store(),
        pollInterval: const Duration(milliseconds: 70),
        commandConfirmationWindow: const Duration(milliseconds: 400),
      );
      controller = ConsoleController(repository);
      await run(() async {
        server.modes['/feeder/feed'] = 'busy-skip';
        final command = await submit(ConsoleAction.feed);
        expect((await result(command)).status, ConsoleCommandStatus.unknown);
        await controller.retry();
        expect(controller.state!.equipment.feederConfirmed, isTrue);
        expect(controller.state!.equipment.feederRunning, isFalse);
        expect(
          (await repository.getCommand(command.id))!.message,
          contains('Whether this request executed remains unknown'),
        );
        expect(server.paths.where((p) => p == '/feeder/feed').length, 1);
        expect(
          (await result(await submit(ConsoleAction.lightOff))).status,
          ConsoleCommandStatus.confirmed,
        );
        expect(
          controller.state!.uncertainCommands.map((c) => c.id),
          contains(command.id),
        );
      });
    },
  );
  test(
    'retract true without observed movement never claims full-stroke completion',
    () async {
      await repository.dispose();
      repository = Esp32ConsoleRepository(
        configurationStore: Store(),
        pollInterval: const Duration(milliseconds: 70),
        commandConfirmationWindow: const Duration(milliseconds: 400),
      );
      controller = ConsoleController(repository);
      await run(() async {
        server.modes['/syringeA/retract'] = 'busy-skip';
        final command = await submit(ConsoleAction.pumpARetract);
        expect((await result(command)).status, ConsoleCommandStatus.unknown);
        expect(controller.state!.equipment.pumpA.active, isFalse);
        expect(server.paths.where((p) => p == '/syringeA/retract').length, 1);
      });
    },
  );
  test(
    'changing configuration cancels old command generation with no replay',
    () => run(() async {
      server.commandDelay = const Duration(milliseconds: 300);
      final command = await submit(ConsoleAction.feed);
      await until(() => server.paths.contains('/feeder/feed'));
      await repository.configureHost('192.168.100.101');
      await controller.retry();
      expect(
        (await repository.getCommand(command.id))!.status,
        ConsoleCommandStatus.unknown,
      );
      expect(repository.configuredHost, '192.168.100.101');
      expect(server.paths.where((p) => p == '/feeder/feed').length, 1);
      expect(server.maximum, 1);
    }),
  );
  test(
    'unreachable before submission failed; reconnect restores local independently',
    () => run(() async {
      await server.server.close(force: true);
      final command = await submit(ConsoleAction.lightOff);
      expect((await result(command)).status, ConsoleCommandStatus.failed);
      await controller.retry();
      expect(controller.canSubmit(ConsoleAction.feed), isFalse);
      expect(controller.state!.cloudConnected, isNull);
      await server.open();
      await controller.retry();
      await until(() => controller.state!.localConnected);
      expect(controller.canSubmit(ConsoleAction.feed), isTrue);
      expect(server.paths, isNot(contains('/led/off')));
    }),
  );
  test(
    'disappearance after submit unknown and recovery never replays feeder',
    () => run(() async {
      server.closeOnCommand = true;
      final command = await submit(ConsoleAction.feed);
      expect((await result(command)).status, ConsoleCommandStatus.unknown);
      await controller.retry();
      expect(controller.state!.readingsStale, isTrue);
      server.closeOnCommand = false;
      await server.open();
      server.apply(ConsoleAction.feed);
      await controller.retry();
      await until(
        () =>
            controller.state!.commands[ConsoleActuator.feeder]?.status ==
            ConsoleCommandStatus.confirmed,
      );
      expect(server.paths.where((p) => p == '/feeder/feed').length, 1);
    }),
  );
  test(
    'target status unavailable retains unknown then recovers from normal polling',
    () => run(() async {
      server.statusErrors.add('/uv/status');
      final command = await submit(ConsoleAction.uvOn);
      await until(() => controller.state!.equipment.uvConfirmed == false);
      expect(
        (await repository.getCommand(command.id))!.status,
        ConsoleCommandStatus.confirming,
      );
      server.statusErrors.clear();
      await controller.retry();
      await until(
        () =>
            controller.state!.commands[ConsoleActuator.uv]?.status ==
            ConsoleCommandStatus.confirmed,
      );
      expect(server.paths.where((p) => p == '/uv/on').length, 1);
    }),
  );
  test(
    'leaving cancels pending result and fresh lifecycle never replays',
    () => run(() async {
      server.commandDelay = const Duration(milliseconds: 350);
      final command = await submit(ConsoleAction.feed);
      await until(() => server.paths.contains('/feeder/feed'));
      controller.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(
        (await repository.getCommand(command.id))!.status,
        ConsoleCommandStatus.unknown,
      );
      controller = ConsoleController(repository)..start();
      await controller.retry();
      expect(server.paths.where((p) => p == '/feeder/feed').length, 1);
    }),
  );
  test(
    'command security permits only exact supported paths, GET, no redirects/credentials',
    () => run(() async {
      final transport = createConsoleHttpTransport();
      addTearDown(transport.close);
      final commands = transport as ConsoleCommandTransport;
      for (final path in [
        '/syringeA/test-dispense',
        '/syringeB/schedule',
        '/led/timer',
        '/feeder/test',
        '/data/backlog/ack',
        '/wifi/disconnect',
        '/arbitrary',
      ]) {
        await expectLater(
          commands.sendCommand(Uri.parse('http://$host$path')),
          throwsFormatException,
        );
      }
      for (final uri in [
        'http://8.8.8.8/led/on',
        'http://user:pass@$host/led/on',
        'http://$host/led/on?duration=1',
        'http://$host:81/led/on',
        'https://$host/led/on',
        'http://$host/led/on#x',
      ]) {
        await expectLater(
          commands.sendCommand(Uri.parse(uri)),
          throwsFormatException,
        );
      }
      final before = server.paths.length;
      server.modes['/led/on'] = 'redirect';
      final response = await commands.sendCommand(
        Uri.parse('http://$host/led/on'),
      );
      expect(response.statusCode, 302);
      expect(server.paths.length, before + 1);
      expect(server.paths.last, '/led/on');
    }),
  );
  testWidgets(
    'live pump panel reports volume, confirms refill, exposes no test dispense',
    (tester) async {
      await HttpOverrides.runWithHttpOverrides(() async {
        await tester.runAsync(() async {
          controller.start();
          await repository.testConnection();
        });
        await tester.pump();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: ConsolePumpSheet(controller: controller, pumpA: true),
              ),
            ),
          ),
        );
        expect(find.text('Dispense 1.00 mL'), findsOneWidget);
        expect(find.text('Stop motor'), findsOneWidget);
        expect(find.text('Retract full stroke'), findsOneWidget);
        expect(find.text('Test dispense'), findsNothing);
        await tester.ensureVisible(find.text('Confirm refill'));
        await tester.tap(find.text('Confirm refill'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('physically checking/refilling'),
          findsOneWidget,
        );
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(server.paths, isNot(contains('/syringeA/refill-confirm')));
        await tester.pumpWidget(const SizedBox());
      }, Sockets(server));
    },
  );
  testWidgets(
    'live lighting sheet shows sending/confirming/reported outcome without mock success',
    (tester) async {
      await HttpOverrides.runWithHttpOverrides(() async {
        server.commandDelay = const Duration(milliseconds: 200);
        await tester.runAsync(() async {
          controller.start();
          await repository.testConnection();
        });
        await tester.pump();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: ConsoleCommandSheet(
                  controller: controller,
                  title: 'Lighting',
                  action: ConsoleAction.lightOff,
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 800));
        await tester.tap(find.byKey(const ValueKey('console-switch-off')));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
        expect(find.textContaining('SENDING'), findsOneWidget);
        for (
          var i = 0;
          i < 80 &&
              controller.state?.commands[ConsoleActuator.light]?.status !=
                  ConsoleCommandStatus.confirmed;
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        expect(find.textContaining('CONFIRMED'), findsOneWidget);
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('console-sheet-current')))
              .data,
          'Off',
        );
        expect(find.text('Completed'), findsNothing);
        await tester.pumpWidget(const SizedBox());
      }, Sockets(server));
    },
  );
}

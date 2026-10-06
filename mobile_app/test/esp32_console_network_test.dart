import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aqualogic/features/console/controllers/console_controller.dart';
import 'package:aqualogic/features/console/data/console_configuration_store.dart';
import 'package:aqualogic/features/console/data/console_http_transport.dart';
import 'package:aqualogic/features/console/data/esp32_console_repository.dart';
import 'package:aqualogic/features/console/models/console_state.dart';
import 'package:aqualogic/features/console/platform/console_display_session.dart';
import 'package:aqualogic/features/console/screens/tank_console_screen.dart';

// A private test destination, redirected only by the test socket factory.
const _host = '192.168.100.100';

class _Store implements ConsoleConfigurationStore {
  String host = _host;
  @override
  Future<String?> readHost() async => host;
  @override
  Future<void> writeHost(String value) async {
    host = value;
  }
}

class _Display implements ConsoleDisplaySession {
  @override
  Future<void> enter() async {}
  @override
  Future<void> exit() async {}
}

class _Server {
  _Server() {
    final objects =
        jsonDecode(
              File(
                'test/fixtures/esp32_248c698/responses.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    fixtures = objects.map((key, value) => MapEntry(key, jsonEncode(value)));
    responses = Map.of(fixtures);
  }
  late final Map<String, String> fixtures;
  late final Map<String, String> responses;
  final errors = <String, int>{};
  final requests = <HttpRequest>[];
  final starts = <DateTime>[];
  HttpServer? server;
  late int port;
  Duration delay = Duration.zero;
  int active = 0;
  int maximum = 0;
  bool redirect = false;
  Future<void> open() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    port = server!.port;
    server!.listen((request) async {
      requests.add(request);
      if (request.uri.path == '/data') starts.add(DateTime.now());
      active++;
      if (active > maximum) maximum = active;
      final wait = delay;
      final status = errors[request.uri.path] ?? 200;
      final body = responses[request.uri.path] ?? '{}';
      try {
        if (wait != Duration.zero) await Future<void>.delayed(wait);
        request.response.statusCode = redirect ? 302 : status;
        if (redirect) {
          request.response.headers.set(HttpHeaders.locationHeader, '/led/on');
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(body);
        await request.response.close();
      } catch (_) {
        // Timeout and disposal deliberately close pending client sockets.
      } finally {
        active--;
      }
    });
  }

  Future<void> close() async {
    await server?.close(force: true);
    server = null;
  }
}

class _Sockets extends HttpOverrides {
  _Sockets(this.server);
  final _Server server;
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)
        ..connectionFactory = (_, _, _) =>
            Socket.startConnect(InternetAddress.loopbackIPv4, server.port);
}

Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 8));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for simulated state');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Server server;
  late _Store store;
  late Esp32ConsoleRepository repository;
  setUp(() async {
    server = _Server();
    await server.open();
    store = _Store();
    repository = Esp32ConsoleRepository(configurationStore: store);
  });
  tearDown(() async {
    await repository.dispose();
    await server.close();
  });
  Future<void> sockets(Future<void> Function() body) =>
      HttpOverrides.runWithHttpOverrides(body, _Sockets(server));

  test(
    'firmware fixtures reach controller through HTTP, without credentials or commands',
    () => sockets(() async {
      final controller = ConsoleController(repository)..start();
      try {
        expect(await repository.testConnection(), isTrue);
        await _until(() => controller.state?.temperature != null);
        final state = controller.state!;
        expect(
          [state.temperature, state.ph, state.tds, state.turbidity],
          [27.3, 7.32, 124, 4.8],
        );
        expect(state.equipment.uvOn, isFalse);
        expect(state.equipment.pumpAStatus, 'RUNNING');
        expect(state.equipment.pumpBStatus, 'IDLE');
        expect(state.cloudConnected, isNull);
        expect(controller.canCommand, isTrue);
        expect(server.requests.map((r) => r.uri.path), server.fixtures.keys);
        for (final request in server.requests) {
          expect(request.method, 'GET');
          expect(request.headers.value(HttpHeaders.hostHeader), _host);
          expect(
            request.headers.value(HttpHeaders.authorizationHeader),
            isNull,
          );
          expect(request.headers.value(HttpHeaders.cookieHeader), isNull);
        }
        expect(server.requests.length, 6);
      } finally {
        controller.dispose();
      }
    }),
  );
  for (final mode in [
    'missing',
    'null',
    'extra',
    'malformed',
    'empty',
    'http',
  ]) {
    test(
      'actual HTTP: $mode data without invented values',
      () => sockets(() async {
        expect(await repository.testConnection(), isTrue);
        final fresh = await repository.getState();
        final data =
            jsonDecode(server.fixtures['/data']!) as Map<String, dynamic>;
        switch (mode) {
          case 'missing':
            data.remove('ph_value');
          case 'null':
            data['ph_value'] = null;
          case 'extra':
            data['unrecognized'] = {'future': true};
          case 'malformed':
            server.responses['/data'] = '{broken';
          case 'empty':
            server.responses['/data'] = '{}';
          case 'http':
            server.errors['/data'] = 503;
        }
        if (['missing', 'null', 'extra'].contains(mode)) {
          server.responses['/data'] = jsonEncode(data);
        }
        final okay = await repository.testConnection();
        final state = await repository.getState();
        if (mode == 'missing' || mode == 'null') {
          expect(okay, isTrue);
          expect(state.ph, isNull);
          expect(state.temperature, 27.3);
          expect(state.quality, isNull);
        } else if (mode == 'extra') {
          expect(okay, isTrue);
          expect(state.ph, 7.32);
        } else {
          expect(okay, isFalse);
          expect(state.observedAt, fresh.observedAt);
          expect(state.ph, 7.32);
          expect(state.readingsStale, isTrue);
          expect(
            state.connectionMessage,
            contains(
              mode == 'http'
                  ? 'HTTP error'
                  : mode == 'empty'
                  ? 'no usable'
                  : 'invalid',
            ),
          );
        }
      }),
    );
  }
  test(
    'one failed status leaves telemetry fresh and pump UNKNOWN',
    () => sockets(() async {
      server.errors['/syringeB/status'] = 500;
      expect(await repository.testConnection(), isTrue);
      final state = await repository.getState();
      expect(state.readingsStale, isFalse);
      expect(state.connection, ConsoleLocalConnection.degraded);
      expect(state.equipment.pumpBStatus, 'UNKNOWN');
      expect(state.equipment.pumpAStatus, 'RUNNING');
      expect(state.equipment.lightConfirmed, isTrue);
      expect(state.cloudConnected, isNull);
    }),
  );
  test(
    'connection refused, stale retention, automatic outage recovery',
    () => sockets(() async {
      await repository.dispose();
      repository = Esp32ConsoleRepository(
        configurationStore: store,
        pollInterval: const Duration(milliseconds: 100),
        staleAfter: const Duration(milliseconds: 250),
      );
      final controller = ConsoleController(repository)..start();
      try {
        await _until(() => controller.state?.localConnected == true);
        await server.close();
        await _until(
          () =>
              controller.state?.connection ==
              ConsoleLocalConnection.disconnected,
        );
        expect(controller.state!.temperature, 27.3);
        expect(controller.state!.readingsStale, isTrue);
        expect(controller.state!.equipment.pumpAStatus, 'UNKNOWN');
        await _until(
          () =>
              controller.state?.connectionMessage?.contains('unreachable') ==
              true,
        );
        expect(controller.state!.cloudConnected, isNull);
        await server.open();
        await _until(
          () =>
              controller.state?.connection == ConsoleLocalConnection.connected,
        );
        expect(controller.state!.readingsStale, isFalse);
        expect(controller.canCommand, isTrue);
      } finally {
        controller.dispose();
      }
    }),
  );
  test(
    'real request deadline times out and recovers',
    () => sockets(() async {
      expect(await repository.testConnection(), isTrue);
      server.delay = const Duration(milliseconds: 3200);
      final watch = Stopwatch()..start();
      expect(await repository.testConnection(), isFalse);
      expect(watch.elapsed, lessThan(const Duration(seconds: 4)));
      expect(
        (await repository.getState()).connectionMessage,
        contains('timed out'),
      );
      expect((await repository.getState()).temperature, 27.3);
      server.delay = Duration.zero;
      expect(await repository.testConnection(), isTrue);
    }),
  );
  test(
    'slow sockets: serial cycles, retries, stop/reenter and host replacement',
    () => sockets(() async {
      await repository.dispose();
      repository = Esp32ConsoleRepository(
        configurationStore: store,
        pollInterval: const Duration(milliseconds: 80),
      );
      server.delay = const Duration(milliseconds: 25);
      var controller = ConsoleController(repository)
        ..start()
        ..start();
      try {
        await Future.wait([
          repository.testConnection(),
          repository.retryLocalConnection(),
        ]);
        expect(server.starts.length, 1);
        await _until(() => server.starts.length >= 3);
        expect(server.maximum, 1);
        controller.dispose();
        await repository.retryLocalConnection();
        final stopped = server.requests.length;
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(server.requests.length, stopped);
        controller = ConsoleController(repository)..start();
        await _until(() => server.requests.length > stopped);
        await repository.configureHost(' 192.168.100.101 ');
        final changed = server.requests.length;
        await repository.testConnection();
        expect(store.host, '192.168.100.101');
        expect(
          server.requests
              .skip(changed)
              .every(
                (r) =>
                    r.headers.value(HttpHeaders.hostHeader) ==
                    '192.168.100.101',
              ),
          isTrue,
        );
        expect(server.maximum, 1);
      } finally {
        controller.dispose();
      }
      await repository.dispose();
      final stopped = server.requests.length;
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(server.requests.length, stopped);
    }),
  );
  test(
    'default polling approximately two seconds',
    () => sockets(() async {
      final controller = ConsoleController(repository)..start();
      try {
        await _until(() => server.starts.length == 2);
        final interval = server.starts[1].difference(server.starts[0]);
        expect(interval, greaterThan(const Duration(milliseconds: 1800)));
        expect(interval, lessThan(const Duration(milliseconds: 2800)));
        expect(server.maximum, 1);
      } finally {
        controller.dispose();
      }
    }),
  );
  test(
    'transport rejects redirects, oversized bodies and non-status destinations',
    () => sockets(() async {
      final transport = createConsoleHttpTransport();
      try {
        server.redirect = true;
        await expectLater(
          transport.get(Uri.http(_host, '/data')),
          throwsA(isA<ConsoleReadFailure>()),
        );
        expect(server.requests.any((r) => r.uri.path == '/led/on'), isFalse);
        server.redirect = false;
        server.responses['/data'] = 'x' * 65537;
        await expectLater(
          transport.get(Uri.http(_host, '/data')),
          throwsFormatException,
        );
        final count = server.requests.length;
        for (final uri in [
          Uri.http(_host, '/led/on'),
          Uri.http(_host, '/data', {'a': '1'}),
          Uri.parse('http://user:secret@$_host/data'),
          Uri.parse('https://$_host/data'),
          Uri.parse('http://$_host:81/data'),
          Uri.parse('http://127.0.0.1/data'),
          Uri.parse('http://8.8.8.8/data'),
          Uri.parse('http://example.com/data'),
          Uri.parse('http://$_host/data#fragment'),
        ]) {
          await expectLater(transport.get(uri), throwsFormatException);
        }
        expect(server.requests.length, count);
      } finally {
        transport.close();
      }
    }),
  );
  test(
    'closing transport during actual socket work is safe and terminal',
    () => sockets(() async {
      server.delay = const Duration(milliseconds: 200);
      final transport = createConsoleHttpTransport();
      final pending = transport.get(Uri.http(_host, '/data'));
      final outcome = expectLater(pending, throwsA(isA<ConsoleReadFailure>()));
      await _until(() => server.requests.isNotEmpty);
      transport.close();
      transport.close();
      await outcome;
      await expectLater(
        transport.get(Uri.http(_host, '/data')),
        throwsStateError,
      );
    }),
  );

  testWidgets(
    'actual HTTP reaches landscape Console; rebuild and exit lifecycle',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(740, 360));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await sockets(() async {
        await tester.runAsync(() => repository.testConnection());

        final screen = TankConsoleScreen(
          repository: repository,
          ownsRepository: true,
          displaySession: _Display(),
        );
        await tester.pumpWidget(MaterialApp(home: screen));

        for (var tick = 0; tick < 100 && server.requests.length < 12; tick++) {
          await tester.pump();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
        }
        await tester.pump();
        expect(server.requests.length, 12);

        expect(find.textContaining('27.3', findRichText: true), findsOneWidget);
        expect(find.text('Running'), findsOneWidget);
        expect(find.textContaining('Cloud · Unknown'), findsOneWidget);
        expect(
          find.textContaining('Live ESP32 · local control'),
          findsOneWidget,
        );
        final count = server.requests.length;
        await tester.pumpWidget(
          MaterialApp(
            home: TankConsoleScreen(
              repository: repository,
              ownsRepository: true,
              displaySession: _Display(),
            ),
          ),
        );
        await tester.pump();
        expect(server.requests.length, count);
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 150));
        });
        expect(server.requests.length, count);
        expect(tester.takeException(), isNull);
      });
    },
  );
}

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aqualogic/features/console/controllers/console_controller.dart';
import 'package:aqualogic/features/console/data/console_configuration_store.dart';
import 'package:aqualogic/features/console/data/console_http_transport.dart';
import 'package:aqualogic/features/console/data/esp32_console_repository.dart';
import 'package:aqualogic/features/console/models/console_command.dart';
import 'package:aqualogic/features/console/models/console_state.dart';
import 'package:aqualogic/features/console/screens/tank_console_screen.dart';
import 'package:aqualogic/features/console/platform/console_display_session.dart';
import 'package:aqualogic/features/console/widgets/console_endpoint_settings.dart';

class _Store implements ConsoleConfigurationStore {
  _Store([this.host = '192.168.1.42']);
  String? host;
  @override
  Future<String?> readHost() async => host;
  @override
  Future<void> writeHost(String value) async {
    host = value;
  }
}

class _Transport implements ConsoleHttpTransport {
  final responses = <String, String>{
    '/data': jsonEncode({
      'temp_c': 27.3,
      'temp_status': 'NORMAL',
      'ph_value': 7.32,
      'ph_status': 'NORMAL',
      'tds_ppm': 124,
      'tds_status': 'NORMAL',
      'turbidity_ntu': 4.8,
      'turbidity_status': 'CLEAR',
      'overall_status': 'GOOD',
    }),
    '/led/status':
        '{"led_on":true,"remaining_ms":0,"total_on_ms":10,"schedule_enabled":true,"sched_on":"08:00","sched_off":"20:00"}',
    '/uv/status':
        '{"led_on":false,"remaining_ms":0,"total_on_ms":0,"schedule_enabled":false,"sched_on":"08:00","sched_off":"20:00"}',
    '/feeder/status':
        '{"feeding":false,"feed_count":1,"last_fed":"08:00","open_angle":90,"duration_ms":1000,"schedule":[]}',
    '/syringeA/status':
        '{"active":true,"remaining_ml":3.5,"volume_known":true,"clock_synced":true,"schedule":[]}',
    '/syringeB/status':
        '{"active":false,"volume_known":false,"refill_required":true,"schedule":[]}',
  };
  final calls = <Uri>[];
  Object? error;
  Duration delay = Duration.zero;
  int active = 0;
  int maximum = 0;
  bool closed = false;
  @override
  Future<String> get(Uri uri) async {
    calls.add(uri);
    active++;
    if (active > maximum) maximum = active;
    try {
      if (delay != Duration.zero) await Future<void>.delayed(delay);
      if (error != null) throw error!;
      return responses[uri.path] ?? '{}';
    } finally {
      active--;
    }
  }

  @override
  void close() {
    closed = true;
  }
}

class _Display implements ConsoleDisplaySession {
  @override
  Future<void> enter() async {}
  @override
  Future<void> exit() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Store store;
  late _Transport transport;
  late Esp32ConsoleRepository repository;
  setUp(() {
    store = _Store();
    transport = _Transport();
    repository = Esp32ConsoleRepository(
      configurationStore: store,
      transport: transport,
    );
  });
  tearDown(() async {
    await repository.dispose();
  });

  test(
    'unconfigured console stays unavailable and sends no requests',
    () async {
      await repository.dispose();
      repository = Esp32ConsoleRepository(
        configurationStore: _Store(null),
        transport: transport,
      );
      expect(await repository.testConnection(), isFalse);
      final state = await repository.getState();
      expect(state.temperature, isNull);
      expect(state.equipment.pumpAStatus, 'UNKNOWN');
      expect(transport.calls, isEmpty);
    },
  );

  test('freshness expires even without another successful cycle', () async {
    await repository.dispose();
    repository = Esp32ConsoleRepository(
      configurationStore: store,
      transport: transport,
      staleAfter: const Duration(milliseconds: 40),
    );
    await repository.testConnection();
    await Future<void>.delayed(const Duration(milliseconds: 65));
    final state = await repository.getState();
    expect(state.temperature, 27.3);
    expect(state.readingsStale, isTrue);
    expect(state.connection, ConsoleLocalConnection.disconnected);
    expect(state.equipment.pumpAStatus, 'UNKNOWN');
  });

  test(
    'an empty valid JSON response retains previous readings as stale, never fresh fallback',
    () async {
      await repository.testConnection();
      final receipt = (await repository.getState()).observedAt;
      transport.responses['/data'] = '{}';
      expect(await repository.testConnection(), isFalse);
      final state = await repository.getState();
      expect(state.temperature, 27.3);
      expect(state.ph, 7.32);
      expect(state.observedAt, receipt);
      expect(state.readingsStale, isTrue);
      expect(state.isSimulated, isFalse);
    },
  );

  test(
    'valid firmware data and all five equipment states map without guesses',
    () async {
      expect(await repository.testConnection(), isTrue);
      final state = await repository.getState();
      expect(state.temperature, 27.3);
      expect(state.ph, 7.32);
      expect(state.tds, 124);
      expect(state.turbidity, 4.8);
      expect(state.quality, ConsoleWaterQuality.normal);
      expect(state.connection, ConsoleLocalConnection.connected);
      expect(state.isSimulated, isFalse);
      expect(state.cloudConnected, isNull);
      expect(state.equipment.lightOn, isTrue);
      expect(state.equipment.uvOn, isFalse);
      expect(state.equipment.feederRunning, isFalse);
      expect(state.equipment.pumpAStatus, 'RUNNING');
      expect(state.equipment.pumpBStatus, 'IDLE');
      expect(transport.calls.length, 6);
    },
  );
  test(
    'missing and invalid values are unavailable, legitimate zero is retained',
    () async {
      transport.responses['/data'] =
          '{"ph_value":null,"temp_c":"bad","tds_ppm":0,"overall_status":"GOOD"}';
      await repository.testConnection();
      final state = await repository.getState();
      expect(state.temperature, isNull);
      expect(state.ph, isNull);
      expect(state.turbidity, isNull);
      expect(state.tds, 0);
      expect(state.quality, isNull);
      expect(state.connection, ConsoleLocalConnection.degraded);
    },
  );
  test(
    'no valid readings means no fabricated update time or successful test',
    () async {
      transport.responses['/data'] = '{}';
      expect(await repository.testConnection(), isFalse);
      expect((await repository.getState()).observedAt, isNull);
    },
  );
  test(
    'disconnected temperature sentinel and unknown quality remain unavailable',
    () async {
      transport.responses['/data'] =
          '{"temp_c":-127,"ph_value":7,"tds_ppm":1,"turbidity_ntu":2,"overall_status":"invented"}';
      await repository.testConnection();
      expect((await repository.getState()).temperature, isNull);
      expect((await repository.getState()).quality, isNull);
    },
  );
  for (final body in ['not json', '[]', 'null']) {
    test(
      'malformed /data $body produces offline state without throwing',
      () async {
        transport.responses['/data'] = body;
        expect(await repository.testConnection(), isFalse);
        expect((await repository.getState()).temperature, isNull);
        expect(
          (await repository.getState()).connection,
          ConsoleLocalConnection.disconnected,
        );
      },
    );
  }
  test(
    'missing malformed pump status and strict boolean parsing never assume idle',
    () async {
      transport.responses['/syringeA/status'] = '{"active":"false"}';
      transport.responses['/syringeB/status'] = 'malformed';
      transport.responses['/uv/status'] = '{"uv_on":true}';
      await repository.testConnection();
      final state = await repository.getState();
      expect(state.equipment.pumpAStatus, 'UNKNOWN');
      expect(state.equipment.pumpBStatus, 'UNKNOWN');
      expect(state.equipment.uvConfirmed, isFalse);
      expect(state.equipment.lightConfirmed, isTrue);
      expect(state.connection, ConsoleLocalConnection.degraded);
    },
  );
  test(
    'timeout retains last known values, ages offline, and recovers independently of cloud',
    () async {
      var now = DateTime(2026, 10, 6);
      await repository.dispose();
      repository = Esp32ConsoleRepository(
        configurationStore: store,
        transport: transport,
        clock: () => now,
      );
      await repository.testConnection();
      final received = (await repository.getState()).observedAt;
      transport.error = TimeoutException('ESP32 timeout');
      now = now.add(const Duration(seconds: 2));
      expect(await repository.testConnection(), isFalse);
      var state = await repository.getState();
      expect(state.temperature, 27.3);
      expect(state.observedAt, received);
      expect(state.readingsStale, isTrue);
      expect(state.connection, ConsoleLocalConnection.degraded);
      now = now.add(const Duration(seconds: 12));
      await repository.retryLocalConnection();
      expect(
        (await repository.getState()).connection,
        ConsoleLocalConnection.disconnected,
      );
      expect((await repository.getState()).cloudConnected, isNull);
      transport.error = null;
      expect(await repository.testConnection(), isTrue);
      expect((await repository.getState()).readingsStale, isFalse);
      expect((await repository.getState()).cloudConnected, isNull);
    },
  );
  test(
    'concurrent listeners retries and slow polling share one serial cycle; disposal stops it',
    () async {
      await repository.dispose();
      transport.delay = const Duration(milliseconds: 10);
      repository = Esp32ConsoleRepository(
        configurationStore: store,
        transport: transport,
        pollInterval: const Duration(milliseconds: 15),
      );
      final first = repository.watchState().listen((_) {});
      final second = repository.watchState().listen((_) {});
      await Future.wait([
        repository.retryLocalConnection(),
        repository.retryLocalConnection(),
      ]);
      expect(transport.maximum, 1);
      expect(transport.calls.where((uri) => uri.path == '/data').length, 1);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(transport.maximum, 1);
      await first.cancel();
      await second.cancel();
      await repository.dispose();
      final count = transport.calls.length;
      await Future<void>.delayed(const Duration(milliseconds: 70));
      expect(transport.calls.length, count);
      expect(transport.closed, isTrue);
    },
  );
  test(
    'host configuration persists across repository instances without cloud',
    () async {
      await repository.configureHost('  aqualogic.local  ');
      expect(store.host, 'aqualogic.local');
      final next = Esp32ConsoleRepository(
        configurationStore: store,
        transport: _Transport(),
      );
      await next.getState();
      expect(next.configuredHost, 'aqualogic.local');
      await next.dispose();
      await expectLater(
        repository.configureHost('https://example.com'),
        throwsFormatException,
      );
      expect(store.host, 'aqualogic.local');
    },
  );
  test(
    'secure settings use a separate persistent key and validate before writing',
    () async {
      final values = <String, String>{};
      const channel = MethodChannel(
        'plugins.it_nomads.com/flutter_secure_storage',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            final args = Map<String, dynamic>.from(call.arguments as Map);
            if (call.method == 'write') {
              values[args['key'] as String] = args['value'] as String;
            }
            if (call.method == 'read') return values[args['key']];
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final secure = SecureConsoleConfigurationStore(
        storage: const FlutterSecureStorage(),
      );
      await secure.writeHost('192.168.4.1');
      expect(await SecureConsoleConfigurationStore().readHost(), '192.168.4.1');
      expect(values.keys, [SecureConsoleConfigurationStore.key]);
    },
  );
  test(
    'host validation rejects URLs ports malformed IP and public destinations',
    () {
      for (final host in [
        '',
        '999.1.1.1',
        '192.168.1',
        '1.2.3.4',
        '192.168.1.1:80',
        'http://192.168.1.1',
        'user@esp32',
        'evil.com',
        '../data',
      ]) {
        expect(
          () => ConsoleEndpoint.parse(host),
          throwsFormatException,
          reason: host,
        );
      }
      for (final host in [
        '10.0.0.1',
        '172.16.0.1',
        '192.168.4.1',
        'esp32',
        'aqualogic.local',
      ]) {
        expect(ConsoleEndpoint.parse(host).host, host);
      }
    },
  );
  test(
    'transport refuses actuator paths and public destinations before networking',
    () async {
      final client = createConsoleHttpTransport();
      addTearDown(client.close);
      await expectLater(
        client.get(Uri.parse('http://192.168.1.42/led/on')),
        throwsFormatException,
      );
      await expectLater(
        client.get(Uri.parse('http://8.8.8.8/data')),
        throwsFormatException,
      );
      await expectLater(
        client.get(Uri.parse('http://192.168.1.42/data?extra=1')),
        throwsFormatException,
      );
    },
  );
  test(
    'all live commands fail without sending requests and controller blocks them',
    () async {
      final controller = ConsoleController(repository)..start();
      await repository.testConnection();
      expect(controller.canCommand, isFalse);
      final count = transport.calls.length;
      expect(await controller.submit(ConsoleAction.lightOn), isNull);
      await expectLater(repository.setLight(true), throwsUnsupportedError);
      await expectLater(repository.setUV(true), throwsUnsupportedError);
      await expectLater(repository.feed(), throwsUnsupportedError);
      expect(transport.calls.length, count);
      controller.dispose();
    },
  );
  testWidgets('configuration UI gracefully validates and saves a local host', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ConsoleEndpointSettings(store: store)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('console-host')),
      'bad/path',
    );
    await tester.tap(find.text('Save host'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Enter a private'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('console-host')),
      '192.168.4.1',
    );
    await tester.tap(find.text('Save host'));
    await tester.pumpAndSettle();
    expect(store.host, '192.168.4.1');
    expect(find.text('Test Connection'), findsOneWidget);
  });

  for (final scenario in [
    'connected',
    'partial',
    'timeout',
    'invalid',
    'unreachable',
    'http',
  ]) {
    testWidgets(
      'Test Connection UI reports $scenario using the injected repository',
      (tester) async {
        if (scenario == 'partial') {
          transport.responses['/syringeA/status'] = '{}';
        }
        if (scenario == 'timeout') {
          transport.error = TimeoutException('offline');
        }
        if (scenario == 'invalid') {
          transport.responses['/data'] = '<html>wrong device</html>';
        }
        if (scenario == 'unreachable') {
          transport.error = const ConsoleReadFailure(
            'ESP32 unreachable. Check that Android and ESP32 are on the same Wi-Fi and confirm the address.',
          );
        }
        if (scenario == 'http') {
          transport.error = const ConsoleReadFailure(
            'ESP32 returned an HTTP error. Confirm the address and expected AquaLogic firmware.',
          );
        }
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ConsoleEndpointSettings(
                store: store,
                createRepository: () => Esp32ConsoleRepository(
                  configurationStore: store,
                  transport: transport,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('console-host')),
          '192.168.4.1',
        );
        await tester.tap(find.text('Test Connection'));
        await tester.pumpAndSettle();
        expect(store.host, '192.168.4.1');
        expect(
          transport.calls.every((uri) => uri.host == '192.168.4.1'),
          isTrue,
        );
        expect(
          find.textContaining(switch (scenario) {
            'timeout' => 'ESP32 timed out',
            'invalid' => 'invalid or unexpected',
            'unreachable' => 'same Wi-Fi',
            'http' => 'HTTP error',
            'partial' => 'Some data is unavailable',
            _ => 'ESP32 connection verified',
          }),
          findsOneWidget,
        );
        expect(transport.closed, isTrue);
      },
    );
  }
  testWidgets(
    'live landscape monitor shows unknown cloud and read-only real pump status',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(740, 360));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await repository.testConnection();
      await tester.pumpWidget(
        MaterialApp(
          home: TankConsoleScreen(
            repository: repository,
            displaySession: _Display(),
            initiallyLocked: false,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.textContaining('Cloud · Unknown'), findsOneWidget);
      expect(find.textContaining('Live ESP32 · local control'), findsOneWidget);
      expect(find.text('Running'), findsOneWidget);
      expect(find.text('Simulated data'), findsNothing);
      await tester.tap(find.byTooltip('Lighting details'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byKey(const ValueKey('console-switch-off')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await repository.dispose();
    },
  );
}

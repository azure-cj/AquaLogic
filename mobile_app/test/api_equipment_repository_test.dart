import 'dart:convert';

import 'package:aqualogic/features/auth/models/auth_user.dart';
import 'package:aqualogic/features/auth/models/user_role.dart';
import 'package:aqualogic/features/control/data/api_equipment_repository.dart';
import 'package:aqualogic/features/control/models/equipment_models.dart';
import 'package:aqualogic/features/control/screens/equipment_screen.dart';
import 'package:aqualogic/features/tanks/models/tank_info.dart';
import 'package:aqualogic/shared/models/aqualogic_status.dart';
import 'package:aqualogic/shared/network/api_client.dart';
import 'package:aqualogic/shared/network/api_failure.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final _clients = <MockClient>[];
final _apiClients = <ApiClient>[];

void main() {
  tearDown(() {
    for (final client in _apiClients) {
      client.close();
    }
    for (final client in _clients) {
      client.close();
    }
    _apiClients.clear();
    _clients.clear();
  });

  test(
    'maps registered device, five actuator states, and lifecycle history',
    () async {
      final requests = <http.Request>[];
      final repository = _repository((request) async {
        requests.add(request);
        return switch (request.url.path) {
          '/devices' => _ok([_device(), _device(id: 'other-tank', tankId: 77)]),
          '/tanks/42/actuators/status' => _ok(_status()),
          '/tanks/42/actuators/history' => _ok(_history()),
          _ => _notFound(),
        };
      });

      final devices = await repository.listDevices(tankId: '42');
      expect(devices, hasLength(1));
      expect(devices.single.id, 'bridge-42');
      expect(devices.single.connection, DeviceConnectionStatus.online);
      expect(devices.single.lastSeenAt, DateTime.utc(2026, 9, 25, 3));

      final overview = await repository.load(
        tankId: '42',
        device: devices.single,
      );

      expect(repository.isLiveData, isTrue);
      expect(repository.supportsCommandSimulation, isFalse);
      expect(overview.statusFailure, isNull);
      expect(overview.historyFailure, isNull);
      expect(overview.historyHasNextPage, isTrue);
      expect(overview.devices.map((item) => item.kind), [
        EquipmentKind.uv,
        EquipmentKind.led,
        EquipmentKind.feeder,
        EquipmentKind.pumpA,
        EquipmentKind.pumpB,
      ]);
      expect(overview.devices.map((item) => item.name), [
        'UV Sterilizer',
        'LED Lighting',
        'Automatic Feeder',
        'Pump A',
        'Pump B',
      ]);
      expect(overview.devices[0].stateLabel, 'On');
      expect(overview.devices[0].scheduleLabel, 'Device schedule 02:00–03:00');
      expect(overview.devices[1].stateLabel, 'Off');
      expect(overview.devices[2].stateLabel, 'Idle');
      expect(overview.devices[2].scheduleLabel, contains('08:00, 14:00'));
      expect(overview.devices[3].stateLabel, 'Idle');
      expect(overview.devices[4].stateLabel, 'No state reported');
      expect(overview.devices[0].connection, DeviceConnectionStatus.online);
      expect(overview.devices[0].lastActionLabel, 'Turn on · Queued');
      expect(overview.commandHistory.map((item) => item.status), [
        CommandStatus.queued,
        CommandStatus.executing,
        CommandStatus.succeeded,
        CommandStatus.failed,
        CommandStatus.expired,
        CommandStatus.outcomeUnknown,
      ]);
      expect(overview.commandHistory[2].actionLabel, 'Feed now');
      expect(overview.commandHistory[5].detail, contains('could not confirm'));
      expect(requests.map((request) => request.method), everyElement('GET'));
      expect(requests.map((request) => request.url.path), [
        '/devices',
        '/tanks/42/actuators/status',
        '/tanks/42/actuators/history',
      ]);
      expect(requests[1].url.queryParameters, {'device_id': 'bridge-42'});
      expect(requests[2].url.queryParameters, {
        'device_id': 'bridge-42',
        'page': '1',
        'page_size': '10',
      });
      expect(
        requests.every((request) => !request.url.path.endsWith('/commands')),
        isTrue,
      );
    },
  );

  test(
    'handles disabled connectivity and unknown actuator types explicitly',
    () async {
      final repository = _repository((request) async {
        if (request.url.path == '/devices') {
          return _ok([_device(status: 'disabled')]);
        }
        if (request.url.path == '/tanks/42/actuators/status') {
          return _ok(
            _status(
              freshness: 'unknown',
              extraActuator: {
                'actuator': 'heater',
                'state': null,
                'refreshed_at': null,
              },
            ),
          );
        }
        return _ok(_history(items: []));
      });
      final device = (await repository.listDevices(tankId: '42')).single;
      final overview = await repository.load(tankId: '42', device: device);

      expect(device.connection, DeviceConnectionStatus.disabled);
      expect(
        overview.devices.first.connection,
        DeviceConnectionStatus.disabled,
      );
      expect(overview.devices.last.kind, EquipmentKind.unknown);
      expect(overview.devices.last.name, 'Unrecognized equipment');
      expect(overview.commandHistory, isEmpty);
    },
  );

  test('history failure does not discard current status', () async {
    final repository = _repository((request) async {
      if (request.url.path == '/devices') return _ok([_device()]);
      if (request.url.path == '/tanks/42/actuators/status') {
        return _ok(_status());
      }
      if (request.url.path == '/tanks/42/actuators/history') {
        return http.Response('{"detail":"hidden"}', 500);
      }
      return _notFound();
    });
    final device = (await repository.listDevices(tankId: '42')).single;
    final overview = await repository.load(tankId: '42', device: device);

    expect(overview.devices, hasLength(5));
    expect(overview.statusFailure, isNull);
    expect(overview.historyFailure?.kind, ApiFailureKind.server);
    expect(overview.commandHistory, isEmpty);
  });

  test(
    '409 ambiguity stays a conflict while successful history is retained',
    () async {
      final repository = _repository((request) async {
        if (request.url.path == '/devices') return _ok([_device()]);
        if (request.url.path == '/tanks/42/actuators/status') {
          return http.Response('{"detail":"ambiguous"}', 409);
        }
        if (request.url.path == '/tanks/42/actuators/history') {
          return _ok(_history());
        }
        return _notFound();
      });
      final device = (await repository.listDevices(tankId: '42')).single;
      final overview = await repository.load(tankId: '42', device: device);

      expect(overview.statusFailure?.kind, ApiFailureKind.conflict);
      expect(overview.statusFailure?.message, contains('ambiguous'));
      expect(overview.devices, isEmpty);
      expect(overview.historyFailure, isNull);
      expect(overview.commandHistory, hasLength(6));
    },
  );

  test(
    'Staff-only 403 is preserved as permission state, not auth failure',
    () async {
      final repository = _repository((request) async {
        if (request.url.path == '/devices') {
          return http.Response('{"detail":"Admin access is required"}', 403);
        }
        return _notFound();
      });

      await expectLater(
        repository.listDevices(tankId: '42'),
        throwsA(
          isA<ApiFailure>()
              .having(
                (failure) => failure.kind,
                'kind',
                ApiFailureKind.forbidden,
              )
              .having(
                (failure) => failure.isUnauthenticated,
                'unauthenticated',
                false,
              ),
        ),
      );
    },
  );

  testWidgets('live Staff equipment access is blocked before any request', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final repository = _repository((request) async {
      requests.add(request);
      return _notFound();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: EquipmentScreen(
          tank: _liveTank,
          user: _staff,
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('restricted to Admin accounts'), findsOneWidget);
    expect(requests, isEmpty);
    expect(find.byType(OutlinedButton), findsNothing);
  });

  testWidgets('live Owner equipment view is read-only and only performs GETs', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final repository = _repository((request) async {
      requests.add(request);
      return switch (request.url.path) {
        '/devices' => _ok([_device()]),
        '/tanks/42/actuators/status' => _ok(_status()),
        '/tanks/42/actuators/history' => _ok(_history()),
        _ => _notFound(),
      };
    });

    await tester.pumpWidget(
      MaterialApp(
        home: EquipmentScreen(
          tank: _liveTank,
          user: _owner,
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Physical controls are not available'),
      findsOneWidget,
    );
    expect(find.text('UV Sterilizer'), findsOneWidget);
    expect(find.byType(OutlinedButton), findsNothing);
    expect(requests.map((request) => request.method), everyElement('GET'));
    expect(
      requests.any((request) => request.url.path.contains('/commands')),
      isFalse,
    );
  });
}

const _liveTank = TankInfo(
  initial: 'R',
  name: 'Reef Alpha',
  subtitle: 'Saltwater · 120 L',
  status: 'normal',
  typeLabel: 'Saltwater',
  volumeLabel: '120 L',
  lastFedLabel: 'No feed record',
  description: 'Live backend tank fixture.',
  id: '42',
  isLiveData: true,
);

const _owner = AuthUser(
  id: '1',
  name: 'AquaLogic Owner',
  email: 'owner@example.test',
  role: UserRole.admin,
);

const _staff = AuthUser(
  id: '2',
  name: 'AquaLogic Staff',
  email: 'staff@example.test',
  role: UserRole.staff,
);

ApiEquipmentRepository _repository(
  Future<http.Response> Function(http.Request) handler,
) {
  final client = MockClient(handler);
  final apiClient = ApiClient(
    baseUrl: 'https://api.test',
    httpClient: client,
    requestTimeout: const Duration(seconds: 1),
  );
  apiClient.configureAuthentication(
    accessTokenReader: () => 'test-access',
    accessTokenExpiryReader: () =>
        DateTime.now().toUtc().add(const Duration(hours: 1)),
    refreshAccessToken: () async => false,
  );
  _clients.add(client);
  _apiClients.add(apiClient);
  return ApiEquipmentRepository(apiClient: apiClient);
}

Map<String, Object?> _device({
  String id = 'bridge-42',
  int tankId = 42,
  String status = 'online',
}) => {
  'device_id': id,
  'tank_id': tankId,
  'tank_name': 'Reef 42',
  'is_active': status != 'disabled',
  'created_at': '2026-09-01T00:00:00Z',
  'last_seen_at': '2026-09-25T03:00:00Z',
  'status': status,
};

Map<String, Object?> _status({
  String freshness = 'online',
  Map<String, Object?>? extraActuator,
}) => {
  'tank_id': 42,
  'device_id': 'bridge-42',
  'device_online': freshness == 'online',
  'device_freshness': freshness,
  'last_seen_at': '2026-09-25T03:00:00Z',
  'checked_at': '2026-09-25T03:01:00Z',
  'actuators': [
    {
      'actuator': 'uv',
      'state': {
        'on': true,
        'remaining_ms': 0,
        'total_on_ms': 1200,
        'schedule_enabled': true,
        'on_time': '02:00',
        'off_time': '03:00',
      },
      'refreshed_at': '2026-09-25T03:00:00Z',
    },
    {
      'actuator': 'led',
      'state': {
        'on': false,
        'remaining_ms': 0,
        'total_on_ms': 500,
        'schedule_enabled': false,
        'on_time': '07:00',
        'off_time': '19:00',
      },
      'refreshed_at': '2026-09-25T03:00:00Z',
    },
    {
      'actuator': 'feeder',
      'state': {
        'feeding': false,
        'feed_count': 3,
        'last_fed': '2026-09-25T08:30:00',
        'open_angle': 90,
        'duration_ms': 1000,
        'schedule': [
          {'enabled': true, 'time': '08:00'},
          {'enabled': false, 'time': '11:00'},
          {'enabled': true, 'time': '14:00'},
        ],
      },
      'refreshed_at': '2026-09-25T03:00:00Z',
    },
    {
      'actuator': 'pump_a',
      'state': {
        'active': false,
        'dose_count': 1,
        'last_dispensed': 'never',
        'volume_ml': 5.0,
      },
      'refreshed_at': '2026-09-25T03:00:00Z',
    },
    {'actuator': 'pump_b', 'state': null, 'refreshed_at': null},
    ?extraActuator,
  ],
  'pump_dispense_locks': [],
};

Map<String, Object?> _history({List<Map<String, Object?>>? items}) => {
  'items':
      items ??
      [
        _command(0, 'uv', 'on', 'queued'),
        _command(1, 'led', 'off', 'executing'),
        _command(2, 'feeder', 'feed_now', 'succeeded'),
        _command(3, 'pump_a', 'dispense', 'failed'),
        _command(4, 'pump_b', 'stop', 'expired'),
        _command(5, 'pump_a', 'dispense', 'outcome_unknown'),
      ],
  'page': 1,
  'page_size': 10,
  'total': 6,
  'total_pages': 1,
  'has_previous': false,
  'has_next': true,
  'summary': {
    'total': 6,
    'queued': 1,
    'executing': 1,
    'succeeded': 1,
    'failed': 1,
    'expired': 1,
    'outcome_unknown': 1,
  },
};

Map<String, Object?> _command(
  int id,
  String actuator,
  String action,
  String status,
) => {
  'command_id': 'command-$id',
  'tank_id': 42,
  'device_id': 'bridge-42',
  'actor_user_id': 7,
  'actor_name': 'Admin',
  'actuator': actuator,
  'action': action,
  'payload': <String, Object?>{},
  'status': status,
  'requested_at': '2026-09-25T03:00:00Z',
  'expires_at': '2026-09-25T03:02:00Z',
  'executing_at': null,
  'confirmation_deadline_at': null,
  'outcome_unknown_at': null,
  'execution_at': null,
  'result': null,
  'error': null,
  'physical_verification_user_id': null,
  'physical_verification_actor_name': null,
  'physical_verification_at': null,
  'physical_verification_note': null,
};

http.Response _ok(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json'},
);

http.Response _notFound() => http.Response(
  '{"detail":"missing"}',
  404,
  headers: {'content-type': 'application/json'},
);

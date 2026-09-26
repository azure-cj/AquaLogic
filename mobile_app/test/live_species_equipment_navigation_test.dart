import 'dart:convert';

import 'package:aqualogic/app/control/equipment_repository_scope.dart';
import 'package:aqualogic/app/fish/fish_repository_scope.dart';
import 'package:aqualogic/features/auth/models/auth_user.dart';
import 'package:aqualogic/features/auth/models/user_role.dart';
import 'package:aqualogic/features/control/data/api_equipment_repository.dart';
import 'package:aqualogic/features/fish/data/api_fish_repository.dart';
import 'package:aqualogic/features/sensors/data/mock_sensor_feed.dart';
import 'package:aqualogic/features/tanks/models/tank_info.dart';
import 'package:aqualogic/features/tanks/screens/tank_detail_screen.dart';
import 'package:aqualogic/shared/models/aqualogic_status.dart';
import 'package:aqualogic/shared/network/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late MockClient client;
  late ApiClient apiClient;

  tearDown(() {
    apiClient.close();
    client.close();
  });

  testWidgets('live Tank Detail opens the matching backend species record', (
    tester,
  ) async {
    final requests = <http.Request>[];
    client = MockClient((request) async {
      requests.add(request);
      if (request.url.path == '/fish/77') return _ok(_fish);
      return _notFound();
    });
    apiClient = _client(client);
    final fishRepository = ApiFishRepository(apiClient: apiClient);

    await tester.pumpWidget(
      FishRepositoryScope(
        repository: fishRepository,
        child: MaterialApp(
          home: TankDetailScreen(
            tank: _liveTank,
            snapshot: MockSensorFeed.snapshot(0),
            user: _owner,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Neon Tetra'), findsOneWidget);

    await tester.tap(find.text('Neon Tetra'));
    await tester.pumpAndSettle();

    expect(find.text('Species detail'), findsOneWidget);
    expect(find.text('A schooling fish.'), findsOneWidget);
    expect(find.text('Assigned to Reef Alpha'), findsOneWidget);
    expect(requests.map((request) => request.url.path), ['/fish/77']);
    expect(requests.single.method, 'GET');
  });

  testWidgets('live Tank Detail opens read-only equipment for its tank', (
    tester,
  ) async {
    final requests = <http.Request>[];
    client = MockClient((request) async {
      requests.add(request);
      return switch (request.url.path) {
        '/devices' => _ok([
          {
            'device_id': 'bridge-42',
            'tank_id': 42,
            'tank_name': 'Reef Alpha',
            'is_active': true,
            'created_at': '2026-09-25T02:00:00Z',
            'last_seen_at': '2026-09-25T03:00:00Z',
            'status': 'online',
          },
        ]),
        '/tanks/42/actuators/status' => _ok({
          'tank_id': 42,
          'device_id': 'bridge-42',
          'device_online': true,
          'device_freshness': 'online',
          'last_seen_at': '2026-09-25T03:00:00Z',
          'checked_at': '2026-09-25T03:01:00Z',
          'actuators': [],
          'pump_dispense_locks': [],
        }),
        '/tanks/42/actuators/history' => _ok({
          'items': [],
          'page': 1,
          'page_size': 10,
          'total': 0,
          'total_pages': 0,
          'has_previous': false,
          'has_next': false,
          'summary': {
            'total': 0,
            'queued': 0,
            'executing': 0,
            'succeeded': 0,
            'failed': 0,
            'expired': 0,
            'outcome_unknown': 0,
          },
        }),
        _ => _notFound(),
      };
    });
    apiClient = _client(client);
    final equipmentRepository = ApiEquipmentRepository(apiClient: apiClient);

    await tester.pumpWidget(
      EquipmentRepositoryScope(
        repository: equipmentRepository,
        child: MaterialApp(
          home: TankDetailScreen(
            tank: _liveTank,
            snapshot: MockSensorFeed.snapshot(0),
            user: _owner,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('tank-equipment-entry')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const ValueKey('tank-equipment-entry')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tank-equipment-entry')));
    await tester.pumpAndSettle();

    expect(find.text('Equipment'), findsOneWidget);
    expect(
      find.textContaining('Physical controls are not available'),
      findsOneWidget,
    );
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
      requests.any((request) => request.url.path.contains('/commands')),
      isFalse,
    );
  });
}

ApiClient _client(MockClient httpClient) {
  final value = ApiClient(
    baseUrl: 'https://api.test',
    httpClient: httpClient,
    requestTimeout: const Duration(seconds: 1),
  );
  value.configureAuthentication(
    accessTokenReader: () => 'test-access',
    accessTokenExpiryReader: () =>
        DateTime.now().toUtc().add(const Duration(hours: 1)),
    refreshAccessToken: () async => false,
  );
  return value;
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
  equipmentCount: 1,
  species: [
    TankSpeciesSummary(
      speciesId: '77',
      name: 'Neon Tetra',
      suitability: SpeciesSuitability.suitable,
      count: 2,
    ),
  ],
);

const _owner = AuthUser(
  id: '1',
  name: 'AquaLogic Owner',
  email: 'owner@example.test',
  role: UserRole.admin,
);

const _fish = {
  'id': 77,
  'common_name': 'Neon Tetra',
  'scientific_name': 'Paracheirodon innesi',
  'photo_url': null,
  'description': 'A schooling fish.',
  'category': 'Community',
  'ideal_temp_min': 20,
  'ideal_temp_max': 26,
  'ideal_ph_min': 6.2,
  'ideal_ph_max': 7.3,
  'ideal_tds_min': null,
  'ideal_tds_max': null,
  'diet': null,
  'diet_type': 'Omnivore',
  'compatibility_notes': 'Avoid large predators.',
  'care_tips': 'Keep in a group.',
  'tank_count': 1,
  'assigned_tanks': [
    {'id': 42, 'name': 'Reef Alpha'},
  ],
  'created_at': '2026-09-25T00:00:00Z',
};

http.Response _ok(Object? body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json'},
);

http.Response _notFound() => http.Response(
  '{"detail":"missing"}',
  404,
  headers: {'content-type': 'application/json'},
);

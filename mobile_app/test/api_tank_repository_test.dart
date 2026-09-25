import 'dart:convert';

import 'package:aqualogic/features/sensors/models/sensor_snapshot.dart';
import 'package:aqualogic/features/tanks/data/api_tank_repository.dart';
import 'package:aqualogic/features/tanks/models/tank_info.dart';
import 'package:aqualogic/shared/models/aqualogic_status.dart';
import 'package:aqualogic/shared/network/api_client.dart';
import 'package:aqualogic/shared/network/api_failure.dart';
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
    'fleet mapping preserves numeric identity, backend status, and age',
    () async {
      final requests = <http.Request>[];
      final repository = _repository((request) async {
        requests.add(request);
        return _ok([
          _fleetTank(id: 17, name: 'Reef Alpha', status: 'normal'),
          _fleetTank(id: 18, name: 'Quarantine Bay', status: 'warning'),
          _fleetTank(id: 19, name: 'Nursery West', status: 'critical'),
          _fleetTank(
            id: 20,
            name: 'Offline Reserve',
            status: 'offline',
            age: 1200,
          ),
        ]);
      });

      final tanks = await repository.loadTanks(snapshot: _snapshot);

      expect(repository.isLiveData, isTrue);
      expect(
        requests,
        hasLength(1),
        reason: 'The fleet payload is enough for the directory.',
      );
      expect(requests.single.url.path, '/fleet');
      expect(requests.single.method, 'GET');
      expect(requests.single.headers['authorization'], 'Bearer test-access');
      expect(tanks.map((tank) => tank.tankId), ['17', '18', '19', '20']);
      expect(tanks.map((tank) => tank.status), [
        'normal',
        'warning',
        'critical',
        'offline',
      ]);
      expect(tanks.map((tank) => tank.operationalStatus), [
        OperationalStatus.normal,
        OperationalStatus.warning,
        OperationalStatus.critical,
        OperationalStatus.offline,
      ]);
      expect(tanks[1].name, 'Quarantine Bay');
      expect(tanks[1].locationOrType, 'Location 18');
      expect(tanks[3].lastReportLabel, 'No recent report');
    },
  );

  test(
    'empty fleet remains empty and no retired or demo tanks are inserted',
    () async {
      final repository = _repository((_) async => _ok([]));
      expect(await repository.loadTanks(snapshot: _snapshot), isEmpty);
    },
  );

  test(
    'fleet status is rejected when it is outside the backend contract',
    () async {
      final repository = _repository(
        (_) async => _ok([_fleetTank(id: 1, name: 'Unknown', status: 'stale')]),
      );
      await expectLater(
        repository.loadTanks(snapshot: _snapshot),
        throwsA(isA<ApiFailure>()),
      );
    },
  );

  test(
    'detail maps real metadata, readings, alerts, species and active monitoring',
    () async {
      final requests = <http.Request>[];
      var activeRequests = 0;
      var maxConcurrentRequests = 0;
      final repository = _repository((request) async {
        requests.add(request);
        activeRequests++;
        if (activeRequests > maxConcurrentRequests) {
          maxConcurrentRequests = activeRequests;
        }
        await Future<void>.delayed(const Duration(milliseconds: 5));
        activeRequests--;
        return switch (request.url.path) {
          '/tanks/42' => _ok(_tankDetail()),
          '/tanks/42/operations' => _ok(
            _operations(
              status: 'warning',
              reading: _reading(
                tankId: 42,
                receivedAt: '2026-09-25T02:59:00Z',
                isMock: true,
                temperature: 0,
                ph: 7.25,
                turbidity: 18.5,
                tds: 340,
              ),
              statuses: const {
                'temperature': 'normal',
                'ph': 'warning',
                'turbidity': 'critical',
                'tds': 'normal',
              },
              alerts: [_alert()],
            ),
          ),
          '/tanks/42/monitoring-incidents' => _ok({
            'items': [_incident(id: 901, tankId: 42, state: 'active')],
            'page': 1,
            'page_size': 100,
            'total': 1,
            'total_pages': 1,
            'has_previous': false,
            'has_next': false,
          }),
          '/tanks/42/species-suitability' => _ok({
            'tank_id': 42,
            'status': 'attention',
            'summary_reason': null,
            'evaluated_at': '2026-09-25T03:00:00Z',
            'reading': null,
            'species_counts': {'suitable': 0, 'attention': 1, 'unavailable': 0},
            'species': [
              {
                'fish_species_id': 77,
                'common_name': 'Clownfish',
                'scientific_name': 'Amphiprion ocellaris',
                'status': 'attention',
                'checks': [],
              },
            ],
          }),
          _ => _notFound(),
        };
      });

      final tank = await repository.loadTankDetail('42', snapshot: _snapshot);

      expect(maxConcurrentRequests, 4);
      expect(requests, hasLength(4));
      expect(requests.every((request) => request.method == 'GET'), isTrue);
      expect(
        requests.every(
          (request) => request.headers['authorization'] == 'Bearer test-access',
        ),
        isTrue,
      );
      expect(requests.map((request) => request.url.path).toSet(), {
        '/tanks/42',
        '/tanks/42/operations',
        '/tanks/42/monitoring-incidents',
        '/tanks/42/species-suitability',
      });
      expect(
        requests
            .singleWhere(
              (request) => request.url.path.endsWith('monitoring-incidents'),
            )
            .url
            .queryParameters,
        {'state': 'active', 'page': '1', 'page_size': '100'},
      );
      expect(tank.tankId, '42');
      expect(tank.name, 'Reef 42');
      expect(tank.locationLabel, 'North room');
      expect(tank.typeLabel, 'Marine reef');
      expect(tank.volumeLabel, '320 L');
      expect(tank.lastFedLabel, isEmpty);
      expect(tank.description, 'Backend description');
      expect(tank.operationalStatus, OperationalStatus.warning);
      expect(tank.isLiveData, isTrue);
      expect(tank.assignedSpeciesCount, 1);
      expect(tank.species.single.speciesId, '77');
      expect(tank.species.single.name, 'Clownfish');
      expect(tank.species.single.suitability, SpeciesSuitability.attention);
      expect(tank.issues.map((issue) => issue.category), [
        TankIssueCategory.waterQuality,
        TankIssueCategory.monitoring,
      ]);
      expect(tank.issues.first.severity, TankIssueSeverity.critical);
      expect(tank.issues.last.id, 'monitoring-incident-901');
      expect(tank.operationsAvailable, isTrue);
      expect(tank.monitoringAvailable, isTrue);
      expect(tank.suitabilityAvailable, isTrue);
      expect(tank.equipmentCount, 0);
      expect(tank.recentActivity, isEmpty);

      final readings = {
        for (final reading in tank.readings) reading.parameter: reading,
      };
      expect(readings[SensorParameter.temperature]!.value, '0.0');
      expect(readings[SensorParameter.temperature]!.unit, '°C');
      expect(readings[SensorParameter.ph]!.value, '7.3');
      expect(readings[SensorParameter.ph]!.unit, 'pH');
      expect(readings[SensorParameter.ph]!.condition, ReadingCondition.warning);
      expect(readings[SensorParameter.turbidity]!.value, '18.5');
      expect(readings[SensorParameter.turbidity]!.unit, 'NTU');
      expect(
        readings[SensorParameter.turbidity]!.condition,
        ReadingCondition.critical,
      );
      expect(readings[SensorParameter.tds]!.value, '340');
      expect(readings[SensorParameter.tds]!.unit, 'ppm');
      expect(readings[SensorParameter.temperature]!.isMock, isTrue);
      expect(
        readings[SensorParameter.temperature]!.receivedAt,
        DateTime.utc(2026, 9, 25, 2, 59),
      );
      expect(
        readings[SensorParameter.temperature]!.observedAt,
        DateTime.utc(2026, 9, 25, 2, 58),
      );
      expect(
        readings[SensorParameter.temperature]!.timestampLabel,
        startsWith('Demo reading'),
      );
    },
  );

  test(
    'null and partial readings stay unavailable and never become zero',
    () async {
      final repository = _repository((request) async {
        return switch (request.url.path) {
          '/tanks/42' => _ok(_tankDetail()),
          '/tanks/42/operations' => _ok(
            _operations(
              status: 'normal',
              reading: _reading(
                tankId: 42,
                temperature: 0,
                ph: null,
                turbidity: 0,
                tds: null,
              ),
              statuses: const {
                'temperature': 'normal',
                'ph': 'unavailable',
                'turbidity': 'normal',
                'tds': 'unavailable',
              },
            ),
          ),
          '/tanks/42/monitoring-incidents' => _ok(_emptyIncidentPage()),
          '/tanks/42/species-suitability' => _ok(_emptySuitability()),
          _ => _notFound(),
        };
      });

      final tank = await repository.loadTankDetail('42', snapshot: _snapshot);
      final readings = {
        for (final reading in tank.readings) reading.parameter: reading,
      };
      expect(readings[SensorParameter.temperature]!.value, '0.0');
      expect(readings[SensorParameter.temperature]!.isAvailable, isTrue);
      expect(readings[SensorParameter.ph]!.value, '—');
      expect(readings[SensorParameter.ph]!.isAvailable, isFalse);
      expect(
        readings[SensorParameter.ph]!.condition,
        ReadingCondition.unavailable,
      );
      expect(readings[SensorParameter.turbidity]!.value, '0');
      expect(readings[SensorParameter.turbidity]!.unit, 'NTU');
      expect(readings[SensorParameter.tds]!.value, '—');
    },
  );

  test(
    'explicitly empty latest_reading maps to four missing-reading states',
    () async {
      final repository = _repository((request) async {
        return switch (request.url.path) {
          '/tanks/42' => _ok(_tankDetail()),
          '/tanks/42/operations' => _ok(
            _operations(status: 'offline', reading: null),
          ),
          '/tanks/42/monitoring-incidents' => _ok(_emptyIncidentPage()),
          '/tanks/42/species-suitability' => _ok(_emptySuitability()),
          _ => _notFound(),
        };
      });

      final tank = await repository.loadTankDetail('42', snapshot: _snapshot);
      expect(tank.operationalStatus, OperationalStatus.offline);
      expect(tank.lastReportLabel, 'No recent report');
      expect(tank.readings, hasLength(4));
      expect(tank.readings.map((item) => item.value), everyElement('—'));
      expect(
        tank.readings.map((item) => item.condition),
        everyElement(ReadingCondition.unavailable),
      );
      expect(
        tank.readings.map((item) => item.timestampLabel),
        everyElement('No reading received'),
      );
    },
  );

  test(
    'stale values remain visible as last known and offline stays separate',
    () async {
      final repository = _repository((request) async {
        return switch (request.url.path) {
          '/tanks/42' => _ok(_tankDetail()),
          '/tanks/42/operations' => _ok(
            _operations(
              status: 'offline',
              reading: _reading(tankId: 42, temperature: 24.6),
              statuses: const {
                'temperature': 'offline',
                'ph': 'offline',
                'turbidity': 'offline',
                'tds': 'offline',
              },
            ),
          ),
          '/tanks/42/monitoring-incidents' => _ok(_emptyIncidentPage()),
          '/tanks/42/species-suitability' => _ok(_emptySuitability()),
          _ => _notFound(),
        };
      });

      final tank = await repository.loadTankDetail('42', snapshot: _snapshot);
      expect(tank.operationalStatus, OperationalStatus.offline);
      expect(tank.readings.first.value, '24.6');
      expect(tank.readings.first.condition, ReadingCondition.stale);
      expect(tank.readings.first.timestampLabel, startsWith('Last known'));
      expect(
        tank.issues,
        isEmpty,
        reason:
            'An offline tank is not itself a water alert or necessarily a detected incident.',
      );
    },
  );

  test('secondary failures preserve real tank and operations data', () async {
    final repository = _repository((request) async {
      return switch (request.url.path) {
        '/tanks/42' => _ok(_tankDetail()),
        '/tanks/42/operations' => _ok(
          _operations(status: 'normal', reading: _reading(tankId: 42)),
        ),
        '/tanks/42/monitoring-incidents' || '/tanks/42/species-suitability' =>
          _response(503, {'detail': 'private server detail'}),
        _ => _notFound(),
      };
    });

    final tank = await repository.loadTankDetail('42', snapshot: _snapshot);
    expect(tank.name, 'Reef 42');
    expect(tank.operationsAvailable, isTrue);
    expect(tank.readings.first.value, '26.2');
    expect(tank.monitoringAvailable, isFalse);
    expect(tank.suitabilityAvailable, isFalse);
    expect(tank.species.single.name, 'Clownfish');
    expect(tank.species.single.suitability, SpeciesSuitability.unavailable);
  });

  test(
    'operations failure does not convert phone/API failure into offline tank',
    () async {
      final repository = _repository((request) async {
        return switch (request.url.path) {
          '/tanks/42' => _ok(_tankDetail()),
          '/tanks/42/operations' => _response(503, {
            'detail': 'backend detail',
          }),
          '/tanks/42/monitoring-incidents' => _ok(_emptyIncidentPage()),
          '/tanks/42/species-suitability' => _ok(_emptySuitability()),
          _ => _notFound(),
        };
      });

      final tank = await repository.loadTankDetail('42', snapshot: _snapshot);
      expect(tank.operationsAvailable, isFalse);
      expect(tank.status, 'unknown');
      expect(tank.readings, isEmpty);
      expect(tank.monitoringLabel, 'Status unavailable');
    },
  );

  test('tank 404 is distinct from null latest sensor reading', () async {
    final repository = _repository((request) async {
      if (request.url.path == '/tanks/42') {
        return _response(404, {'detail': 'not found'});
      }
      return _ok(_operations(status: 'offline', reading: null));
    });

    await expectLater(
      repository.loadTankDetail('42', snapshot: _snapshot),
      throwsA(
        isA<ApiFailure>().having(
          (failure) => failure.kind,
          'kind',
          ApiFailureKind.notFound,
        ),
      ),
    );
  });

  test('active monitoring mapping excludes resolved records', () async {
    final repository = _repository((request) async {
      return switch (request.url.path) {
        '/tanks/42' => _ok(_tankDetail()),
        '/tanks/42/operations' => _ok(
          _operations(status: 'normal', reading: _reading(tankId: 42)),
        ),
        '/tanks/42/monitoring-incidents' => _ok({
          ..._emptyIncidentPage(),
          'items': [
            _incident(id: 1, tankId: 42, state: 'resolved'),
            _incident(id: 2, tankId: 42, state: 'active'),
          ],
        }),
        '/tanks/42/species-suitability' => _ok(_emptySuitability()),
        _ => _notFound(),
      };
    });
    final tank = await repository.loadTankDetail('42', snapshot: _snapshot);
    final monitoring = tank.issues
        .where((issue) => issue.category == TankIssueCategory.monitoring)
        .toList();
    expect(monitoring, hasLength(1));
    expect(monitoring.single.id, 'monitoring-incident-2');
  });
}

final _snapshot = SensorSnapshot(
  temperatureC: 25,
  tempStatus: 'NORMAL',
  ph: 7,
  phStatus: 'NORMAL',
  turbidityRaw: 10,
  turbidityStatus: 'NORMAL',
  tdsRaw: 150,
  tdsStatus: 'NORMAL',
  overallStatus: 'NORMAL',
  isOnline: true,
  updatedAt: DateTime.utc(2026, 9, 25),
);

ApiTankRepository _repository(
  Future<http.Response> Function(http.Request) handler,
) {
  final client = MockClient(handler);
  _clients.add(client);
  final apiClient =
      ApiClient(baseUrl: 'https://aqualogic.example.test', httpClient: client)
        ..configureAuthentication(
          accessTokenReader: () => 'test-access',
          accessTokenExpiryReader: () =>
              DateTime.now().toUtc().add(const Duration(hours: 1)),
          refreshAccessToken: () async => false,
        );
  _apiClients.add(apiClient);
  return ApiTankRepository(apiClient: apiClient);
}

http.Response _ok(Object body) => _response(200, body);

http.Response _notFound() => _response(404, {'detail': 'not found'});

http.Response _response(int statusCode, Object body) => http.Response(
  jsonEncode(body),
  statusCode,
  headers: const {'content-type': 'application/json'},
);

Map<String, Object?> _fleetTank({
  required int id,
  required String name,
  required String status,
  int age = 10,
  int speciesCount = 1,
  Object? latestReading,
}) => {
  'id': id,
  'public_id': 'public-$id',
  'name': name,
  'location': 'Location $id',
  'customer': null,
  'latest_reading': latestReading,
  'status': status,
  'last_reading_at': '2026-09-25T08:00:00Z',
  'reporting_age_seconds': age,
  'active_warning_count': status == 'warning' ? 1 : 0,
  'active_critical_count': status == 'critical' ? 1 : 0,
  'active_monitoring_incident_count': status == 'offline' ? 1 : 0,
  'species_care_status': 'suitable',
  'assigned_species_count': speciesCount,
};

Map<String, Object?> _tankDetail() => {
  'id': 42,
  'public_id': 'public-42',
  'name': 'Reef 42',
  'location': 'North room',
  'description': 'Backend description',
  'is_public': true,
  'customer_id': null,
  'feeding_schedule': 'not displayed',
  'public_care_notes': null,
  'tank_code': 'R-42',
  'habitat_label': 'Marine reef',
  'water_type': 'saltwater',
  'volume_liters': 320,
  'established_on': '2024-05-06',
  'hero_image_url': null,
  'created_at': '2024-01-01T00:00:00Z',
  'lifecycle': 'active',
  'retired_at': null,
  'retired_by_user_id': null,
  'retired_by_user_name': null,
  'retirement_note': null,
  'fish_species': [
    {
      'id': 77,
      'common_name': 'Clownfish',
      'scientific_name': 'Amphiprion ocellaris',
      'photo_url': null,
      'description': null,
      'category': 'Marine',
      'ideal_temp_min': 24,
      'ideal_temp_max': 27,
      'ideal_ph_min': 8,
      'ideal_ph_max': 8.4,
      'ideal_tds_min': null,
      'ideal_tds_max': null,
      'diet': null,
      'diet_type': null,
      'compatibility_notes': null,
      'care_tips': null,
      'created_at': '2024-01-01T00:00:00Z',
      'tank_count': 1,
    },
  ],
  'customer': null,
};

Map<String, Object?> _operations({
  required String status,
  required Object? reading,
  Map<String, String> statuses = const {
    'temperature': 'normal',
    'ph': 'normal',
    'turbidity': 'normal',
    'tds': 'normal',
  },
  List<Map<String, Object?>> alerts = const [],
}) => {
  'tank_id': 42,
  'evaluated_at': '2026-09-25T03:00:00Z',
  'status': status,
  'latest_reading': reading,
  'parameter_statuses': statuses,
  'active_alerts': alerts,
};

Map<String, Object?> _reading({
  required int tankId,
  String timestamp = '2026-09-25T02:58:00Z',
  String receivedAt = '2026-09-25T02:59:00Z',
  bool isMock = false,
  double? temperature = 26.2,
  double? ph = 8.1,
  double? turbidity = 11,
  double? tds = 250,
}) => {
  'id': 501,
  'device_id': 'bridge-9',
  'tank_id': tankId,
  'timestamp': timestamp,
  'received_at': receivedAt,
  'temperature': temperature,
  'ph': ph,
  'turbidity': turbidity,
  'tds': tds,
  'dissolved_oxygen': null,
  'ammonia': null,
  'is_mock': isMock,
};

Map<String, Object?> _alert() => {
  'id': 201,
  'tank_id': 42,
  'reading_id': 501,
  'parameter': 'turbidity',
  'severity': 'critical',
  'message': 'Turbidity exceeds the configured threshold.',
  'is_resolved': false,
  'resolved_at': null,
  'resolved_by_user_id': null,
  'resolution_source': null,
  'created_at': '2026-09-25T02:57:00Z',
};

Map<String, Object?> _incident({
  required int id,
  required int tankId,
  required String state,
}) => {
  'id': id,
  'tank_id': tankId,
  'tank_name': 'Reef 42',
  'tank_lifecycle': 'active',
  'state': state,
  'started_at': '2026-09-25T02:30:00Z',
  'detected_at': '2026-09-25T02:40:00Z',
  'last_reading_received_at': '2026-09-25T02:10:00Z',
  'last_report_age_seconds': 3000,
  'resolved_at': state == 'resolved' ? '2026-09-25T02:50:00Z' : null,
  'resolution_reason': state == 'resolved' ? 'reporting_recovered' : null,
  'recovery_reading_id': state == 'resolved' ? 502 : null,
  'duration_seconds': 900,
};

Map<String, Object?> _emptyIncidentPage() => {
  'items': <Object?>[],
  'page': 1,
  'page_size': 100,
  'total': 0,
  'total_pages': 0,
  'has_previous': false,
  'has_next': false,
};

Map<String, Object?> _emptySuitability() => {
  'tank_id': 42,
  'status': 'unavailable',
  'summary_reason': 'no_species_assigned',
  'evaluated_at': '2026-09-25T03:00:00Z',
  'reading': null,
  'species_counts': {'suitable': 0, 'attention': 0, 'unavailable': 0},
  'species': <Object?>[],
};

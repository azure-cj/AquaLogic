import 'dart:convert';
import 'dart:io';

import 'package:aqualogic/features/home/data/api_home_repository.dart';
import 'package:aqualogic/features/home/models/home_dashboard_data.dart';
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
    'maps fleet, alerts, and paginated monitoring data concurrently',
    () async {
      final requests = <http.Request>[];
      final repository = _repository((request) async {
        requests.add(request);
        switch (request.url.path) {
          case '/fleet':
            return _ok([
              _fleetTank(id: 1, name: 'Display Reef', status: 'normal'),
              _fleetTank(
                id: 2,
                name: 'Quarantine',
                status: 'warning',
                reportingAge: 300,
              ),
              _fleetTank(id: 3, name: 'Nursery', status: 'critical'),
              _fleetTank(
                id: 4,
                name: 'Saltwater A',
                status: 'offline',
                reportingAge: 720,
                incidentCount: 1,
                lastReadingAt: '2026-09-25T01:00:00+00:00',
              ),
            ]);
          case '/alerts':
            return _ok([
              _alert(
                id: 21,
                tankId: 2,
                severity: 'warning',
                parameter: 'ph',
                createdAt: '2026-09-25T08:00:00+08:00',
              ),
              _alert(
                id: 22,
                tankId: 3,
                severity: 'critical',
                parameter: 'tds',
                createdAt: '2026-09-25T07:00:00+08:00',
              ),
              _alert(
                id: 23,
                tankId: 1,
                severity: 'critical',
                parameter: 'temperature',
                isResolved: true,
              ),
            ]);
          case '/monitoring-incidents':
            return _ok(
              _incidentPage(
                total: 201,
                totalPages: 3,
                hasNext: true,
                items: [
                  _incident(
                    id: 91,
                    tankId: 4,
                    tankName: 'Saltwater A',
                    lastReportAge: 720,
                  ),
                ],
              ),
            );
          default:
            return _notFound();
        }
      });

      final data = await repository.load();

      expect(requests, hasLength(3));
      expect(requests.map((request) => request.method), everyElement('GET'));
      expect(
        requests.map((request) => request.headers['authorization']),
        everyElement('Bearer test-access'),
      );
      final incidentRequest = requests.singleWhere(
        (request) => request.url.path == '/monitoring-incidents',
      );
      expect(incidentRequest.url.queryParameters, {
        'state': 'active',
        'page': '1',
        'page_size': '100',
      });
      expect(
        requests.where(
          (request) => request.url.path == '/monitoring-incidents',
        ),
        hasLength(1),
        reason: 'The endpoint total is exact; Home only needs its newest page.',
      );

      expect(data.isLiveData, isTrue);
      expect(data.tanks.map((tank) => tank.id), ['1', '2', '3', '4']);
      expect(data.tanks.map((tank) => tank.status), [
        HomeOperationalStatus.normal,
        HomeOperationalStatus.warning,
        HomeOperationalStatus.critical,
        HomeOperationalStatus.offline,
      ]);
      expect(data.tanks[0].lastReportLabel, 'Updated just now');
      expect(data.tanks[1].reportingAgeSeconds, 300);
      expect(data.tanks[1].lastReportLabel, 'Updated 5 minutes ago');
      expect(data.tanks[3].lastReportedAt?.isUtc, isTrue);
      expect(data.normalTankCount, 1);
      expect(data.needsAttentionCount, 2);
      expect(data.offlineTankCount, 1);
      expect(data.monitoring.reportingTankCount, 3);
      expect(data.monitoring.outageCount, 201);
      expect(data.monitoring.incidentDetailsAvailable, isTrue);
      expect(data.alertsAvailable, isTrue);
      expect(data.monitoringIncidentsAvailable, isTrue);
      expect(data.recentActivity, isEmpty);

      expect(data.attentionItems, hasLength(3));
      expect(data.attentionItems[0].type, HomeAttentionType.waterQuality);
      expect(data.attentionItems[0].status, HomeOperationalStatus.critical);
      expect(data.attentionItems[0].sourceId, '22');
      expect(data.attentionItems[0].title, 'Critical TDS reading');
      expect(data.attentionItems[1].type, HomeAttentionType.waterQuality);
      expect(data.attentionItems[1].sourceId, '21');
      expect(data.attentionItems[2].type, HomeAttentionType.monitoring);
      expect(data.attentionItems[2].sourceId, '91');
      expect(
        data.attentionItems[2].message,
        'The last report was received 12 minutes ago.',
      );
    },
  );

  test('empty fleet and empty active sources are healthy live data', () async {
    final repository = _repository((request) async {
      if (request.url.path == '/fleet') return _ok(const []);
      if (request.url.path == '/alerts') return _ok(const []);
      if (request.url.path == '/monitoring-incidents') {
        return _ok(_incidentPage(total: 0, totalPages: 0, items: const []));
      }
      return _notFound();
    });

    final data = await repository.load();

    expect(data.tanks, isEmpty);
    expect(data.attentionItems, isEmpty);
    expect(data.monitoring.totalTankCount, 0);
    expect(data.monitoring.reportingTankCount, 0);
    expect(data.monitoring.outageCount, 0);
    expect(data.recentActivity, isEmpty);
    expect(data.hasPartialFailure, isFalse);
  });

  test('alert endpoint failure preserves fleet-derived water status', () async {
    final repository = _repository((request) async {
      if (request.url.path == '/fleet') {
        return _ok([
          _fleetTank(id: 7, name: 'Quarantine B', status: 'critical'),
        ]);
      }
      if (request.url.path == '/alerts') {
        return _response(503, {'detail': 'internal database detail'});
      }
      if (request.url.path == '/monitoring-incidents') {
        return _ok(_incidentPage(total: 0, totalPages: 0, items: const []));
      }
      return _notFound();
    });

    final data = await repository.load();

    expect(data.alertsAvailable, isFalse);
    expect(data.monitoringIncidentsAvailable, isTrue);
    expect(data.hasPartialFailure, isTrue);
    expect(data.needsAttentionCount, 1);
    expect(data.attentionItems, hasLength(1));
    expect(data.attentionItems.single.status, HomeOperationalStatus.critical);
    expect(data.attentionItems.single.type, HomeAttentionType.waterQuality);
    expect(data.attentionItems.single.sourceId, isNull);
    expect(
      data.attentionItems.single.message,
      contains('backend fleet status'),
    );
  });

  test(
    'incident failure keeps exact fleet incident count and offline state',
    () async {
      final repository = _repository((request) async {
        if (request.url.path == '/fleet') {
          return _ok([
            _fleetTank(
              id: 8,
              name: 'Nursery D',
              status: 'offline',
              incidentCount: 1,
              reportingAge: 950,
            ),
          ]);
        }
        if (request.url.path == '/alerts') return _ok(const []);
        if (request.url.path == '/monitoring-incidents') {
          return _response(503, {'detail': 'internal details'});
        }
        return _notFound();
      });

      final data = await repository.load();

      expect(data.monitoringIncidentsAvailable, isFalse);
      expect(data.monitoring.incidentDetailsAvailable, isFalse);
      expect(data.monitoring.outageCount, 1);
      expect(data.offlineTankCount, 1);
      expect(data.attentionItems.single.type, HomeAttentionType.monitoring);
      expect(data.attentionItems.single.sourceId, isNull);
      expect(
        data.attentionItems.single.message,
        'The last report was received 15 minutes ago.',
      );
    },
  );

  test(
    'fleet failure rejects the whole dashboard with a safe API failure',
    () async {
      final repository = _repository((request) async {
        if (request.url.path == '/fleet') {
          return _response(503, {'detail': 'private database traceback'});
        }
        if (request.url.path == '/alerts') return _ok(const []);
        if (request.url.path == '/monitoring-incidents') {
          return _ok(_incidentPage(total: 0, totalPages: 0, items: const []));
        }
        return _notFound();
      });

      await expectLater(
        repository.load(),
        throwsA(
          isA<ApiFailure>()
              .having((failure) => failure.kind, 'kind', ApiFailureKind.server)
              .having(
                (failure) => failure.message,
                'safe message',
                'AquaLogic is temporarily unavailable.',
              ),
        ),
      );
    },
  );

  test(
    'complete network failure stays distinct from offline tank status',
    () async {
      final repository = _repository(
        (_) async => throw const SocketException('offline'),
      );

      await expectLater(
        repository.load(),
        throwsA(
          isA<ApiFailure>().having(
            (failure) => failure.kind,
            'kind',
            ApiFailureKind.networkUnavailable,
          ),
        ),
      );
    },
  );

  test(
    'unknown fleet status fails closed instead of inventing a category',
    () async {
      final repository = _repository((request) async {
        if (request.url.path == '/fleet') {
          return _ok([_fleetTank(id: 9, name: 'Unknown', status: 'stale')]);
        }
        if (request.url.path == '/alerts') return _ok(const []);
        if (request.url.path == '/monitoring-incidents') {
          return _ok(_incidentPage(total: 0, totalPages: 0, items: const []));
        }
        return _notFound();
      });

      await expectLater(repository.load(), throwsA(isA<ApiFailure>()));
    },
  );
}

ApiHomeRepository _repository(
  Future<http.Response> Function(http.Request) handler,
) {
  final mockClient = MockClient(handler);
  final apiClient =
      ApiClient(
        baseUrl: 'https://aqualogic.example.test',
        httpClient: mockClient,
      )..configureAuthentication(
        accessTokenReader: () => 'test-access',
        accessTokenExpiryReader: () => DateTime.utc(2035),
        refreshAccessToken: () async => true,
      );
  _clients.add(mockClient);
  _apiClients.add(apiClient);
  return ApiHomeRepository(apiClient: apiClient);
}

http.Response _ok(Object? body) => http.Response(
  jsonEncode(body),
  200,
  headers: const {'content-type': 'application/json'},
);

http.Response _response(int status, Object? body) => http.Response(
  jsonEncode(body),
  status,
  headers: const {'content-type': 'application/json'},
);

http.Response _notFound() => _response(404, {'detail': 'not found'});

Map<String, Object?> _fleetTank({
  required int id,
  required String name,
  required String status,
  int? reportingAge,
  int incidentCount = 0,
  String? lastReadingAt = '2026-09-25T08:00:00Z',
}) => {
  'id': id,
  'public_id': 'public-$id',
  'name': name,
  'location': 'Room $id',
  'customer': null,
  'latest_reading': null,
  'status': status,
  'last_reading_at': lastReadingAt,
  'reporting_age_seconds': reportingAge ?? 18,
  'active_warning_count': status == 'warning' ? 1 : 0,
  'active_critical_count': status == 'critical' ? 1 : 0,
  'active_monitoring_incident_count': incidentCount,
  'species_care_status': 'unavailable',
  'assigned_species_count': 0,
};

Map<String, Object?> _alert({
  required int id,
  required int tankId,
  required String severity,
  required String parameter,
  String createdAt = '2026-09-25T08:30:00Z',
  bool isResolved = false,
}) => {
  'id': id,
  'tank_id': tankId,
  'reading_id': 13,
  'parameter': parameter,
  'severity': severity,
  'message': '$parameter is outside its $severity threshold',
  'is_resolved': isResolved,
  'resolved_at': isResolved ? '2026-09-25T09:00:00Z' : null,
  'resolved_by_user_id': null,
  'resolution_source': isResolved ? 'system' : null,
  'created_at': createdAt,
};

Map<String, Object?> _incident({
  required int id,
  required int tankId,
  required String tankName,
  int? lastReportAge,
}) => {
  'id': id,
  'tank_id': tankId,
  'tank_name': tankName,
  'tank_lifecycle': 'active',
  'state': 'active',
  'started_at': '2026-09-25T07:30:00Z',
  'detected_at': '2026-09-25T07:35:00Z',
  'last_reading_received_at': '2026-09-25T07:23:00Z',
  'last_report_age_seconds': lastReportAge,
  'resolved_at': null,
  'resolution_reason': null,
  'recovery_reading_id': null,
  'duration_seconds': 1200,
};

Map<String, Object?> _incidentPage({
  required int total,
  required int totalPages,
  required List<Map<String, Object?>> items,
  bool hasNext = false,
}) => {
  'items': items,
  'page': 1,
  'page_size': 100,
  'total': total,
  'total_pages': totalPages,
  'has_previous': false,
  'has_next': hasNext,
};

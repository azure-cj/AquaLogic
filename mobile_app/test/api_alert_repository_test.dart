import 'dart:convert';
import 'dart:io';

import 'package:aqualogic/features/alerts/data/api_alert_repository.dart';
import 'package:aqualogic/features/alerts/models/alert_info.dart';
import 'package:aqualogic/features/sensors/data/mock_sensor_feed.dart';
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
    'maps active alerts by ID, tank name, severity, parameter, and UTC time',
    () async {
      final requests = <http.Request>[];
      final repository = _repository((request) async {
        requests.add(request);
        if (request.url.path == '/alerts') {
          return _ok([
            _alert(
              id: 41,
              tankId: 9,
              parameter: 'ph',
              severity: 'warning',
              createdAt: '2026-09-25T09:00:00+08:00',
            ),
            _alert(
              id: 40,
              tankId: 9,
              parameter: 'tds',
              severity: 'critical',
              createdAt: '2026-09-25T08:50:00+08:00',
            ),
          ]);
        }
        if (request.url.path == '/tanks') {
          return _ok([
            {'id': 9, 'name': 'Saltwater Reef', 'lifecycle': 'active'},
          ]);
        }
        return _notFound();
      });

      final alerts = await repository.loadWaterQualityAlerts(
        snapshot: MockSensorFeed.snapshot(0),
        history: false,
      );

      expect(alerts.map((alert) => alert.id), ['40', '41']);
      expect(alerts.first.tankId, '9');
      expect(alerts.first.tankName, 'Saltwater Reef');
      expect(alerts.first.parameter, 'TDS');
      expect(alerts.first.severity, AlertSeverity.critical);
      expect(alerts.first.startedAt, DateTime.utc(2026, 9, 25, 0, 50));
      expect(alerts.first.isActive, isTrue);
      expect(requests.map((request) => request.headers['authorization']), [
        'Bearer test-access',
        'Bearer test-access',
      ]);
      expect(requests.map((request) => request.url.path), [
        '/alerts',
        '/tanks',
      ]);
      expect(requests.last.url.queryParameters, {'lifecycle': 'all'});
    },
  );

  test(
    'history asks for resolved records and preserves operator/system source',
    () async {
      final requests = <http.Request>[];
      final repository = _repository((request) async {
        requests.add(request);
        if (request.url.path == '/alerts/history') {
          return _ok([
            _alert(
              id: 31,
              tankId: 2,
              parameter: 'temperature',
              severity: 'warning',
              isResolved: true,
              resolutionSource: 'operator',
              resolvedAt: '2026-09-24T22:10:00Z',
            ),
            _alert(
              id: 30,
              tankId: 3,
              parameter: 'turbidity',
              severity: 'critical',
              isResolved: true,
              resolutionSource: 'system',
              resolvedAt: '2026-09-24T20:00:00Z',
            ),
            _alert(id: 29, tankId: 2, isResolved: false),
          ]);
        }
        if (request.url.path == '/tanks') {
          return _ok([
            {'id': 2, 'name': 'Retired Tank', 'lifecycle': 'retired'},
            {'id': 3, 'name': 'Nursery', 'lifecycle': 'active'},
          ]);
        }
        return _notFound();
      });

      final history = await repository.loadWaterQualityAlerts(
        snapshot: MockSensorFeed.snapshot(0),
        history: true,
      );

      expect(requests.first.url.path, '/alerts/history');
      expect(requests.first.url.queryParameters, {'resolved': 'true'});
      expect(history.map((alert) => alert.id), ['31', '30']);
      expect(history.first.tankName, 'Retired Tank');
      expect(history.first.statusLabel, 'Handled');
      expect(history.first.resolutionSource, AlertResolutionSource.operator);
      expect(history.first.resolvedAt?.isUtc, isTrue);
      expect(history.last.statusLabel, 'Resolved automatically');
      expect(history.last.resolutionSource, AlertResolutionSource.system);
      expect(history.last.tankName, 'Nursery');
    },
  );

  test(
    'empty active and history alert lists stay healthy without tank lookup',
    () async {
      final requests = <http.Request>[];
      final repository = _repository((request) async {
        requests.add(request);
        if (request.url.path == '/alerts' ||
            request.url.path == '/alerts/history') {
          return _ok(const []);
        }
        return _notFound();
      });

      final active = await repository.loadWaterQualityAlerts(
        snapshot: MockSensorFeed.snapshot(0),
        history: false,
      );
      final history = await repository.loadWaterQualityAlerts(
        snapshot: MockSensorFeed.snapshot(0),
        history: true,
      );

      expect(active, isEmpty);
      expect(history, isEmpty);
      expect(requests, hasLength(2));
      expect(requests.every((request) => request.url.path != '/tanks'), isTrue);
    },
  );

  test(
    'unknown resolution source stays neutral; unknown severity fails safely',
    () async {
      final neutral = _repository((request) async {
        if (request.url.path == '/alerts/history') {
          return _ok([
            _alert(
              id: 8,
              tankId: 2,
              isResolved: true,
              resolutionSource: 'future_source',
            ),
          ]);
        }
        if (request.url.path == '/tanks') {
          return _ok([
            {'id': 2, 'name': 'Tank B'},
          ]);
        }
        return _notFound();
      });
      final history = await neutral.loadWaterQualityAlerts(
        snapshot: MockSensorFeed.snapshot(0),
        history: true,
      );
      expect(history.single.statusLabel, 'Resolved');

      final invalid = _repository((request) async {
        if (request.url.path == '/alerts') {
          return _ok([_alert(id: 9, tankId: 2, severity: 'emergency')]);
        }
        return _ok([
          {'id': 2, 'name': 'Tank B'},
        ]);
      });
      await expectLater(
        invalid.loadWaterQualityAlerts(
          snapshot: MockSensorFeed.snapshot(0),
          history: false,
        ),
        throwsA(
          isA<ApiFailure>().having(
            (failure) => failure.message,
            'safe message',
            'AquaLogic returned alert data that could not be read.',
          ),
        ),
      );
    },
  );

  test(
    'monitoring uses actual page contract and maps each resolution reason',
    () async {
      final requests = <http.Request>[];
      final repository = _repository((request) async {
        requests.add(request);
        if (request.url.path == '/monitoring-incidents') {
          final isResolved = request.url.queryParameters['state'] == 'resolved';
          return _ok(
            _incidentPage(
              page: int.parse(request.url.queryParameters['page']!),
              items: isResolved
                  ? [
                      _incident(
                        id: 99,
                        reason: 'reporting_recovered',
                        state: 'resolved',
                      ),
                      _incident(
                        id: 98,
                        reason: 'monitoring_disabled',
                        state: 'resolved',
                      ),
                      _incident(
                        id: 97,
                        reason: 'tank_retired',
                        state: 'resolved',
                      ),
                    ]
                  : [_incident(id: 100)],
              total: isResolved ? 3 : 1,
              totalPages: 1,
            ),
          );
        }
        return _notFound();
      });

      final active = await repository.loadMonitoringIncidents(
        snapshot: MockSensorFeed.snapshot(0),
        history: false,
        page: 1,
      );
      final history = await repository.loadMonitoringIncidents(
        snapshot: MockSensorFeed.snapshot(0),
        history: true,
        page: 1,
      );

      expect(requests[0].url.queryParameters, {
        'state': 'active',
        'page': '1',
        'page_size': '25',
      });
      expect(requests[1].url.queryParameters, {
        'state': 'resolved',
        'page': '1',
        'page_size': '25',
      });
      expect(active.items.single.isActive, isTrue);
      expect(active.total, 1);
      expect(history.items.map((item) => item.lifecycleLabel), [
        'Recovered',
        'Monitoring disabled',
        'Tank retired',
      ]);
      expect(
        history.items[0].resolutionMessage,
        contains('Reporting recovered'),
      );
      expect(
        history.items[1].resolutionMessage,
        contains('Monitoring was disabled'),
      );
      expect(history.items[2].resolutionMessage, contains('tank was retired'));
      expect(
        history.items.every((item) => item.startedAt?.isUtc ?? false),
        isTrue,
      );
    },
  );

  test(
    'monitoring pagination sends the requested page and uses has_next',
    () async {
      final requests = <http.Request>[];
      final repository = _repository((request) async {
        requests.add(request);
        if (request.url.path == '/monitoring-incidents') {
          final page = int.parse(request.url.queryParameters['page']!);
          return _ok(
            _incidentPage(
              page: page,
              total: 26,
              totalPages: 2,
              hasNext: page == 1,
              items: [_incident(id: page == 1 ? 52 : 51, state: 'resolved')],
            ),
          );
        }
        return _notFound();
      });

      final first = await repository.loadMonitoringIncidents(
        snapshot: MockSensorFeed.snapshot(0),
        history: true,
        page: 1,
      );
      final second = await repository.loadMonitoringIncidents(
        snapshot: MockSensorFeed.snapshot(0),
        history: true,
        page: 2,
      );

      expect(first.hasNext, isTrue);
      expect(second.hasNext, isFalse);
      expect(second.page, 2);
      expect(requests.last.url.queryParameters['page'], '2');
      expect(requests.last.url.queryParameters['state'], 'resolved');
    },
  );

  test('resolve is bodyless PUT and maps the idempotent response', () async {
    final requests = <http.Request>[];
    final repository = _repository((request) async {
      requests.add(request);
      if (request.url.path == '/alerts/123/resolve') {
        return _ok(
          _alert(
            id: 123,
            tankId: 2,
            isResolved: true,
            resolutionSource: 'operator',
            resolvedByUserId: 7,
            resolvedAt: '2026-09-25T10:00:00Z',
          ),
        );
      }
      if (request.url.path == '/tanks') {
        return _ok([
          {'id': 2, 'name': 'Tank B'},
        ]);
      }
      return _notFound();
    });

    final alert = await repository.resolveAlert('123');

    expect(requests.first.method, 'PUT');
    expect(requests.first.url.path, '/alerts/123/resolve');
    expect(requests.first.body, isEmpty);
    expect(requests.first.headers['authorization'], 'Bearer test-access');
    expect(alert.statusLabel, 'Handled');
    expect(alert.resolvedByUserId, 7);
    expect(alert.tankName, 'Tank B');
  });

  test(
    '401 retries once with refreshed authorization and 403 does not refresh',
    () async {
      var accessToken = 'expired-access';
      var refreshCount = 0;
      var resolveCount = 0;
      final repository = _repository(
        (request) async {
          if (request.url.path == '/alerts/15/resolve') {
            resolveCount++;
            if (request.headers['authorization'] == 'Bearer expired-access') {
              return _response(401, {'detail': 'private detail'});
            }
            return _ok(
              _alert(
                id: 15,
                tankId: 2,
                isResolved: true,
                resolutionSource: 'operator',
              ),
            );
          }
          if (request.url.path == '/tanks') {
            return _ok([
              {'id': 2, 'name': 'Tank B'},
            ]);
          }
          return _notFound();
        },
        accessTokenReader: () => accessToken,
        refreshAccessToken: () async {
          refreshCount++;
          accessToken = 'fresh-access';
          return true;
        },
      );
      final resolved = await repository.resolveAlert('15');
      expect(resolved.statusLabel, 'Handled');
      expect(refreshCount, 1);
      expect(resolveCount, 2);

      var forbiddenRefreshes = 0;
      final forbidden = _repository(
        (_) async => _response(403, {'detail': 'private detail'}),
        refreshAccessToken: () async {
          forbiddenRefreshes++;
          return true;
        },
      );
      await expectLater(
        forbidden.resolveAlert('15'),
        throwsA(
          isA<ApiFailure>().having(
            (failure) => failure.kind,
            'kind',
            ApiFailureKind.forbidden,
          ),
        ),
      );
      expect(forbiddenRefreshes, 0);
    },
  );

  for (final entry in const {
    400: ApiFailureKind.business,
    401: ApiFailureKind.unauthenticated,
    403: ApiFailureKind.forbidden,
    404: ApiFailureKind.notFound,
    409: ApiFailureKind.conflict,
    422: ApiFailureKind.validation,
    429: ApiFailureKind.rateLimited,
    500: ApiFailureKind.server,
  }.entries) {
    test(
      'resolve normalizes HTTP ${entry.key} and hides backend details',
      () async {
        final repository = _repository(
          (_) async => _response(entry.key, {
            'detail': 'private database constraint and credentials',
          }),
          refreshAccessToken: () async => false,
        );

        await expectLater(
          repository.resolveAlert('901'),
          throwsA(
            isA<ApiFailure>()
                .having((failure) => failure.kind, 'kind', entry.value)
                .having((failure) => failure.statusCode, 'status', entry.key)
                .having(
                  (failure) => failure.message,
                  'safe message',
                  isNot(contains('private database')),
                ),
          ),
        );
      },
    );
  }

  test(
    'resolve normalizes socket failures without exposing socket text',
    () async {
      final repository = _repository(
        (_) async => throw const SocketException('private host information'),
      );

      await expectLater(
        repository.resolveAlert('901'),
        throwsA(
          isA<ApiFailure>()
              .having(
                (failure) => failure.kind,
                'kind',
                ApiFailureKind.networkUnavailable,
              )
              .having(
                (failure) => failure.message,
                'safe message',
                isNot(contains('private host')),
              ),
        ),
      );
    },
  );

  test('resolve normalizes request timeouts', () async {
    final repository = _repository((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      return _ok({});
    }, requestTimeout: const Duration(milliseconds: 5));

    await expectLater(
      repository.resolveAlert('901'),
      throwsA(
        isA<ApiFailure>().having(
          (failure) => failure.kind,
          'kind',
          ApiFailureKind.timeout,
        ),
      ),
    );
  });
}

ApiAlertRepository _repository(
  Future<http.Response> Function(http.Request) handler, {
  String Function()? accessTokenReader,
  Future<bool> Function()? refreshAccessToken,
  Duration requestTimeout = const Duration(seconds: 15),
}) {
  final client = MockClient(handler);
  _clients.add(client);
  final apiClient =
      ApiClient(
        baseUrl: 'https://aqualogic.example.test',
        httpClient: client,
        requestTimeout: requestTimeout,
      )..configureAuthentication(
        accessTokenReader: accessTokenReader ?? () => 'test-access',
        accessTokenExpiryReader: () => DateTime.utc(2035),
        refreshAccessToken: refreshAccessToken ?? () async => true,
      );
  _apiClients.add(apiClient);
  return ApiAlertRepository(apiClient: apiClient);
}

Map<String, Object?> _alert({
  required int id,
  int tankId = 2,
  String parameter = 'temperature',
  String severity = 'warning',
  String createdAt = '2026-09-25T08:00:00Z',
  bool isResolved = false,
  String? resolutionSource,
  String? resolvedAt,
  int? resolvedByUserId,
}) => {
  'id': id,
  'tank_id': tankId,
  'reading_id': null,
  'parameter': parameter,
  'severity': severity,
  'message': '$parameter is outside the configured range.',
  'is_resolved': isResolved,
  'created_at': createdAt,
  'resolved_at': resolvedAt,
  'resolved_by_user_id': resolvedByUserId,
  'resolution_source': resolutionSource,
};

Map<String, Object?> _incident({
  required int id,
  String state = 'active',
  String? reason,
}) => {
  'id': id,
  'tank_id': 2,
  'tank_name': 'Tank B',
  'tank_lifecycle': 'active',
  'state': state,
  'started_at': '2026-09-25T07:00:00Z',
  'detected_at': '2026-09-25T07:10:00+00:00',
  'last_reading_received_at': '2026-09-25T06:50:00Z',
  'last_report_age_seconds': 1200,
  'resolved_at': state == 'resolved' ? '2026-09-25T08:00:00Z' : null,
  'resolution_reason': reason,
  'recovery_reading_id': null,
  'duration_seconds': 3600,
};

Map<String, Object?> _incidentPage({
  required List<Map<String, Object?>> items,
  int page = 1,
  int total = 1,
  int totalPages = 1,
  bool hasNext = false,
}) => {
  'items': items,
  'page': page,
  'page_size': 25,
  'total': total,
  'total_pages': totalPages,
  'has_previous': page > 1,
  'has_next': hasNext,
};

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

http.Response _notFound() => _response(404, {'detail': 'Not found'});

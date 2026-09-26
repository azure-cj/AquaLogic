import 'dart:convert';

import 'package:aqualogic/features/fish/data/api_fish_repository.dart';
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
    'directory and detail use authenticated numeric IDs and real fields',
    () async {
      final requests = <http.Request>[];
      final repository = _repository((request) async {
        requests.add(request);
        if (request.url.path == '/fish') return _ok([_species(id: 77)]);
        if (request.url.path == '/fish/77') return _ok(_species(id: 77));
        return _notFound();
      });

      final directory = await repository.list();
      final detail = await repository.findById('77');

      expect(repository.isLiveData, isTrue);
      expect(repository.supportsWaterTypeFilter, isFalse);
      expect(directory, hasLength(1));
      expect(directory.single.speciesId, '77');
      expect(directory.single.name, 'Neon Tetra');
      expect(directory.single.category, 'Community');
      expect(directory.single.careGroup, 'Community');
      expect(directory.single.type, isEmpty);
      expect(directory.single.temperatureRange, '20–26 °C');
      expect(directory.single.phRange, '6.2–7.3');
      expect(directory.single.tdsRange, '100–400 ppm');
      expect(directory.single.diet, 'Pellets and frozen foods');
      expect(directory.single.careNote, 'Keep in a group.');
      expect(directory.single.compatibilityNote, 'Avoid large predators.');
      expect(detail?.speciesId, '77');
      expect(detail?.description, 'A schooling fish.');
      expect(requests.map((request) => request.url.path), [
        '/fish',
        '/fish/77',
      ]);
      expect(requests.map((request) => request.method), ['GET', 'GET']);
      expect(requests.map((request) => request.headers['authorization']), [
        'Bearer test-access',
        'Bearer test-access',
      ]);
    },
  );

  test('empty directory and nullable ranges remain truthful', () async {
    final repository = _repository((request) async {
      if (request.url.path == '/fish') return _ok([]);
      return _ok(
        _species(
          id: 9,
          idealTempMin: null,
          idealTempMax: null,
          idealPhMin: 7.1,
          idealPhMax: null,
          idealTdsMin: null,
          idealTdsMax: null,
          diet: null,
          dietType: null,
          description: null,
          careTips: null,
          compatibilityNotes: null,
        ),
      );
    });

    expect(await repository.list(), isEmpty);
    final species = await repository.findById('9');
    expect(species?.temperatureRange, 'Not specified');
    expect(species?.phRange, '≥ 7.1');
    expect(species?.tdsRange, 'Not specified');
    expect(species?.diet, 'Not specified by AquaLogic.');
    expect(species?.description, isEmpty);
    expect(species?.careNote, isEmpty);
    expect(species?.compatibilityNote, isEmpty);
  });

  test(
    'non-numeric detail identity fails without making an API request',
    () async {
      var requests = 0;
      final repository = _repository((_) async {
        requests++;
        return _notFound();
      });

      await expectLater(
        repository.findById('guppy'),
        throwsA(isA<ApiFailure>()),
      );
      expect(requests, 0);
    },
  );

  test(
    'directory failures normalize without exposing FastAPI detail',
    () async {
      final repository = _repository(
        (_) async => http.Response('{"detail":"private backend text"}', 500),
      );

      await expectLater(
        repository.list(),
        throwsA(
          isA<ApiFailure>()
              .having((failure) => failure.kind, 'kind', ApiFailureKind.server)
              .having(
                (failure) => failure.message,
                'message',
                isNot(contains('private backend text')),
              ),
        ),
      );
    },
  );
}

ApiFishRepository _repository(
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
  return ApiFishRepository(apiClient: apiClient);
}

Map<String, Object?> _species({
  required int id,
  double? idealTempMin = 20,
  double? idealTempMax = 26,
  double? idealPhMin = 6.2,
  double? idealPhMax = 7.3,
  double? idealTdsMin = 100,
  double? idealTdsMax = 400,
  String? diet = 'Pellets and frozen foods',
  String? dietType = 'Omnivore',
  String? description = 'A schooling fish.',
  String? careTips = 'Keep in a group.',
  String? compatibilityNotes = 'Avoid large predators.',
}) => {
  'id': id,
  'common_name': 'Neon Tetra',
  'scientific_name': 'Paracheirodon innesi',
  'photo_url': null,
  'description': description,
  'category': 'Community',
  'ideal_temp_min': idealTempMin,
  'ideal_temp_max': idealTempMax,
  'ideal_ph_min': idealPhMin,
  'ideal_ph_max': idealPhMax,
  'ideal_tds_min': idealTdsMin,
  'ideal_tds_max': idealTdsMax,
  'diet': diet,
  'diet_type': dietType,
  'compatibility_notes': compatibilityNotes,
  'care_tips': careTips,
  'tank_count': 1,
  'assigned_tanks': [
    {'id': 3, 'name': 'Nursery'},
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

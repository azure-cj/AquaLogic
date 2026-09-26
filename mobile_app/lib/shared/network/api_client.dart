import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'api_configuration.dart';
import 'api_failure.dart';

typedef AccessTokenReader = String? Function();
typedef AccessTokenExpiryReader = DateTime? Function();
typedef AccessTokenRefresh = Future<bool> Function();

class ApiResponse {
  const ApiResponse({
    required this.statusCode,
    required this.headers,
    required this.body,
  });

  final int statusCode;
  final Map<String, String> headers;
  final Object? body;
}

/// The shared JSON/HTTP boundary used by mobile API repositories.
class ApiClient {
  ApiClient({
    String baseUrl = ApiConfiguration.baseUrl,
    http.Client? httpClient,
    this.requestTimeout = const Duration(seconds: 15),
  }) : _baseUrl = _validateBaseUrl(baseUrl),
       _httpClient = httpClient ?? http.Client(),
       _ownsClient = httpClient == null;

  final Uri _baseUrl;
  final http.Client _httpClient;
  final bool _ownsClient;
  final Duration requestTimeout;

  AccessTokenReader? _accessTokenReader;
  AccessTokenExpiryReader? _accessTokenExpiryReader;
  AccessTokenRefresh? _accessTokenRefresh;
  Future<bool>? _refreshInFlight;

  void configureAuthentication({
    required AccessTokenReader accessTokenReader,
    required AccessTokenExpiryReader accessTokenExpiryReader,
    required AccessTokenRefresh refreshAccessToken,
  }) {
    _accessTokenReader = accessTokenReader;
    _accessTokenExpiryReader = accessTokenExpiryReader;
    _accessTokenRefresh = refreshAccessToken;
  }

  Future<ApiResponse> get(
    String path, {
    bool authenticated = false,
    Map<String, String> headers = const {},
  }) => request('GET', path, authenticated: authenticated, headers: headers);

  Future<ApiResponse> post(
    String path, {
    Object? body,
    bool authenticated = false,
    Map<String, String> headers = const {},
  }) => request(
    'POST',
    path,
    body: body,
    authenticated: authenticated,
    headers: headers,
  );

  Future<ApiResponse> put(
    String path, {
    Object? body,
    bool authenticated = false,
    Map<String, String> headers = const {},
  }) => request(
    'PUT',
    path,
    body: body,
    authenticated: authenticated,
    headers: headers,
  );

  Future<ApiResponse> delete(
    String path, {
    bool authenticated = false,
    Map<String, String> headers = const {},
  }) => request('DELETE', path, authenticated: authenticated, headers: headers);

  Future<ApiResponse> request(
    String method,
    String path, {
    Object? body,
    bool authenticated = false,
    Map<String, String> headers = const {},
  }) async {
    if (authenticated && _accessTokenRefresh != null) {
      final expiresAt = _accessTokenExpiryReader?.call();
      if (expiresAt != null &&
          !DateTime.now().toUtc().isBefore(
            expiresAt.subtract(const Duration(seconds: 30)),
          )) {
        if (!await _refreshOnce()) throw ApiFailure.fromStatus(401);
      }
    }

    final first = await _send(
      method,
      path,
      body: body,
      authenticated: authenticated,
      headers: headers,
    );

    if (first.statusCode == 401 &&
        authenticated &&
        _accessTokenRefresh != null) {
      final refreshed = await _refreshOnce();
      if (refreshed) {
        final retry = await _send(
          method,
          path,
          body: body,
          authenticated: true,
          headers: headers,
        );
        return _decodeOrThrow(retry);
      }
    }

    return _decodeOrThrow(first);
  }

  Future<bool> _refreshOnce() {
    final inFlight = _refreshInFlight;
    if (inFlight != null) return inFlight;

    final refresh = _accessTokenRefresh!();
    _refreshInFlight = refresh;
    return refresh.whenComplete(() {
      if (identical(_refreshInFlight, refresh)) _refreshInFlight = null;
    });
  }

  Future<http.Response> _send(
    String method,
    String path, {
    Object? body,
    required bool authenticated,
    required Map<String, String> headers,
  }) async {
    final request = http.Request(
      method,
      _baseUrl.resolve(_normalizePath(path)),
    );
    request.headers['accept'] = 'application/json';
    if (body != null) {
      request.headers['content-type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    request.headers.addAll(headers);

    if (authenticated) {
      final token = _accessTokenReader?.call();
      if (token == null || token.isEmpty) {
        throw ApiFailure.fromStatus(401);
      }
      request.headers['authorization'] = 'Bearer $token';
    }

    try {
      return await (() async {
        final streamed = await _httpClient.send(request);
        return http.Response.fromStream(streamed);
      })().timeout(requestTimeout);
    } on TimeoutException {
      throw ApiFailure.timeout();
    } on SocketException {
      throw ApiFailure.networkUnavailable();
    } on http.ClientException {
      throw ApiFailure.networkUnavailable();
    }
  }

  ApiResponse _decodeOrThrow(http.Response response) {
    Object? decoded;
    if (response.bodyBytes.isNotEmpty) {
      try {
        decoded = jsonDecode(utf8.decode(response.bodyBytes));
      } on FormatException {
        if (response.statusCode >= 200 && response.statusCode < 300) {
          throw ApiFailure(
            kind: ApiFailureKind.unknown,
            statusCode: response.statusCode,
            message: 'AquaLogic returned an unreadable response.',
          );
        }
      }
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiFailure.fromStatus(
        response.statusCode,
        headers: response.headers,
        responseBody: decoded,
      );
    }

    return ApiResponse(
      statusCode: response.statusCode,
      headers: Map.unmodifiable(response.headers),
      body: decoded,
    );
  }

  static Uri _validateBaseUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'https' && uri.scheme != 'http')) {
      throw ArgumentError.value(value, 'baseUrl', 'Must be an HTTP(S) URL.');
    }
    if (ApiConfiguration.isReleaseBuild && uri.scheme != 'https') {
      throw ArgumentError.value(
        value,
        'baseUrl',
        'Release builds require HTTPS.',
      );
    }
    return uri.replace(
      path: uri.path.endsWith('/') ? uri.path : '${uri.path}/',
    );
  }

  static String _normalizePath(String value) =>
      value.startsWith('/') ? value.substring(1) : value;

  void close() {
    if (_ownsClient) _httpClient.close();
  }
}

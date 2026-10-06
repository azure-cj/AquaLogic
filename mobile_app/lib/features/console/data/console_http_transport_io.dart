import 'dart:convert';
import 'dart:io';
import 'console_http_transport.dart';
import 'console_configuration_store.dart';

ConsoleHttpTransport createTransport() => _LocalHttpTransport();

class _LocalHttpTransport implements ConsoleHttpTransport {
  final _clients = <HttpClient>{};
  bool _closed = false;
  static const _paths = {
    '/data',
    '/led/status',
    '/uv/status',
    '/feeder/status',
    '/syringeA/status',
    '/syringeB/status',
  };
  @override
  Future<String> get(Uri uri) async {
    if (_closed) throw StateError('Transport disposed');
    ConsoleEndpoint.parse(uri.host);
    if (uri.scheme != 'http' ||
        uri.port != 80 ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        !_paths.contains(uri.path)) {
      throw const FormatException(
        'Only ESP32 read-only status requests are allowed.',
      );
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 3)
      ..findProxy = (_) => 'DIRECT';
    _clients.add(client);
    try {
      return await (() async {
        final addresses = await InternetAddress.lookup(uri.host);
        final address = addresses.where((a) {
          try {
            ConsoleEndpoint.parse(a.address);
            return true;
          } catch (_) {
            return false;
          }
        }).firstOrNull;
        if (address == null) {
          throw const FormatException(
            'Host must resolve to a private Wi-Fi IPv4 address.',
          );
        }
        // Pin this private address; disable redirects and never attach cloud credentials.
        final request = await client.getUrl(uri.replace(host: address.address));
        request.followRedirects = false;
        request.headers.set(HttpHeaders.hostHeader, uri.host);
        final response = await request.close();
        if (response.statusCode != 200) {
          throw HttpException('ESP32 returned HTTP ${response.statusCode}');
        }
        final bytes = <int>[];
        await for (final chunk in response) {
          bytes.addAll(chunk);
          if (bytes.length > 65536) {
            throw const FormatException('ESP32 response too large');
          }
        }
        return utf8.decode(bytes);
      })().timeout(const Duration(seconds: 3));
    } on SocketException {
      throw const ConsoleReadFailure(
        'ESP32 unreachable. Check that Android and ESP32 are on the same Wi-Fi and confirm the address. Try the IP if the hostname cannot be resolved.',
      );
    } on HttpException {
      throw const ConsoleReadFailure(
        'ESP32 returned an HTTP error. Confirm the address and that the expected AquaLogic firmware is running.',
      );
    } finally {
      client.close(force: true);
      _clients.remove(client);
    }
  }

  @override
  void close() {
    _closed = true;
    // Closing a socket may synchronously finish get() and remove its client.
    for (final client in _clients.toList()) {
      client.close(force: true);
    }
    _clients.clear();
  }
}

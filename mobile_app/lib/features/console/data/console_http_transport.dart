import 'console_http_transport_stub.dart'
    if (dart.library.io) 'console_http_transport_io.dart'
    as platform;

abstract interface class ConsoleHttpTransport {
  Future<String> get(Uri uri);
  void close();
}

ConsoleHttpTransport createConsoleHttpTransport() => platform.createTransport();

/// Safe setup guidance, without socket details, addresses or stack traces.
class ConsoleReadFailure implements Exception {
  const ConsoleReadFailure(this.message);
  final String message;
}

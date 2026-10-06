import 'console_http_transport_stub.dart'
    if (dart.library.io) 'console_http_transport_io.dart'
    as platform;

abstract interface class ConsoleHttpTransport {
  Future<String> get(Uri uri);
  void close();
}

ConsoleHttpTransport createConsoleHttpTransport() => platform.createTransport();

/// Separate capability: read clients cannot accidentally issue mutations.
abstract interface class ConsoleCommandTransport {
  Future<ConsoleHttpResponse> sendCommand(Uri uri);
}

class ConsoleHttpResponse {
  const ConsoleHttpResponse(this.statusCode, this.body);
  final int statusCode;
  final String body;
}

class ConsoleCommandFailure implements Exception {
  const ConsoleCommandFailure({required this.mayHaveReachedDevice});
  final bool mayHaveReachedDevice;
}

/// Safe setup guidance, without socket details, addresses or stack traces.
class ConsoleReadFailure implements Exception {
  const ConsoleReadFailure(this.message);
  final String message;
}

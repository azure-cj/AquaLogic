import 'console_http_transport.dart';

ConsoleHttpTransport createTransport() => _UnsupportedTransport();

class _UnsupportedTransport implements ConsoleHttpTransport {
  @override
  Future<String> get(Uri uri) async => throw UnsupportedError(
    'Use Android for local ESP32 monitoring. Browser previews use simulated data.',
  );
  @override
  void close() {}
}

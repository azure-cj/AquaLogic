/// Compile-time API endpoint selection for the native client.
///
/// Debug builds default to the Android emulator's host loopback alias. A
/// physical Android device should pass its development machine's LAN URL with
/// `--dart-define=AQUALOGIC_API_BASE_URL=http://<lan-ip>:8000`.
/// Release builds default to the deployed Railway API.
abstract final class ApiConfiguration {
  static const productionBaseUrl =
      'https://aqualogic-production.up.railway.app';
  static const _developmentBaseUrl = 'http://10.0.2.2:8000';

  static const baseUrl = String.fromEnvironment(
    'AQUALOGIC_API_BASE_URL',
    defaultValue: bool.fromEnvironment('dart.vm.product')
        ? productionBaseUrl
        : _developmentBaseUrl,
  );

  static const isReleaseBuild = bool.fromEnvironment('dart.vm.product');
}

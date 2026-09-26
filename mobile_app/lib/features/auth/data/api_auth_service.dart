import 'package:aqualogic/features/auth/data/auth_api_models.dart';
import 'package:aqualogic/features/auth/data/mock_auth_service.dart';
import 'package:aqualogic/features/auth/data/refresh_cookie.dart';
import 'package:aqualogic/features/auth/data/refresh_credential_store.dart';
import 'package:aqualogic/features/auth/models/auth_user.dart';
import 'package:aqualogic/shared/network/api_client.dart';
import 'package:aqualogic/shared/network/api_failure.dart';

/// Production authentication backed by the deployed FastAPI `/auth/*` routes.
/// Access JWTs stay in this service's memory; only the refresh-cookie value is
/// written to the platform secure store.
class ApiAuthService extends AuthService {
  ApiAuthService({
    ApiClient? apiClient,
    RefreshCredentialStore? credentialStore,
  }) : _apiClient = apiClient ?? ApiClient(),
       _credentialStore = credentialStore ?? SecureRefreshCredentialStore() {
    _apiClient.configureAuthentication(
      accessTokenReader: () => _accessToken,
      accessTokenExpiryReader: () => _accessTokenExpiresAt,
      refreshAccessToken: _refreshAccessToken,
    );
  }

  static const loginPath = '/auth/login';
  static const refreshPath = '/auth/refresh';
  static const currentUserPath = '/auth/me';
  static const logoutPath = '/auth/logout';
  static const changePasswordPath = '/auth/change-password';

  final ApiClient _apiClient;
  final RefreshCredentialStore _credentialStore;

  /// Exposes the authenticated client for production repositories that share
  /// this auth/session lifecycle. Callers must not close it independently.
  ApiClient get apiClient => _apiClient;

  AuthStatus _status = AuthStatus.checking;
  AuthUser? _currentUser;
  String? _accessToken;
  DateTime? _accessTokenExpiresAt;
  int _sessionGeneration = 0;
  Future<void> Function()? _beforeSignOut;

  @override
  AuthStatus get status => _status;

  @override
  AuthUser? get currentUser => _currentUser;

  @override
  int get sessionGeneration => _sessionGeneration;

  /// Lets app composition perform best-effort authenticated cleanup before
  /// this service revokes the current backend session.
  void setBeforeSignOutHook(Future<void> Function()? hook) {
    _beforeSignOut = hook;
  }

  @override
  Future<void> initialize() async {
    _setStatus(AuthStatus.checking);

    String? refreshCredential;
    try {
      refreshCredential = await _credentialStore.read();
    } catch (_) {
      _accessToken = null;
      _currentUser = null;
      _setStatus(AuthStatus.connectionUnavailable);
      return;
    }

    if (refreshCredential == null || refreshCredential.isEmpty) {
      _accessToken = null;
      _currentUser = null;
      _setStatus(AuthStatus.unauthenticated);
      return;
    }

    try {
      final refreshResponse = await _postRefresh(refreshCredential);
      final token = AuthTokenResponse.fromJson(refreshResponse.body);
      await _saveRefreshCredential(
        refreshResponse.headers,
        requireCredential: false,
      );
      _accessToken = token.accessToken;
      _accessTokenExpiresAt = token.expiresAt;

      // The token response also contains a UserRead, but /auth/me is used on
      // cold start so a persisted role/profile is never treated as session
      // truth on this device.
      final meResponse = await _apiClient.get(
        currentUserPath,
        authenticated: true,
      );
      final user = BackendAuthUser.fromMeJson(meResponse.body).toDomain();
      _setUser(user, newSession: true);
    } on ApiFailure catch (failure) {
      if (failure.isUnauthenticated) {
        await _clearLocalSession();
      } else if (failure.retryable ||
          failure.kind == ApiFailureKind.forbidden) {
        _accessToken = null;
        _currentUser = null;
        _setStatus(AuthStatus.connectionUnavailable);
      } else {
        await _clearLocalSession();
      }
    } catch (_) {
      _accessToken = null;
      _currentUser = null;
      _setStatus(AuthStatus.connectionUnavailable);
    }
  }

  @override
  Future<AuthUser?> signIn({
    required String email,
    required String password,
  }) async {
    final response = await _apiClient.post(
      loginPath,
      body: {'email': email.trim(), 'password': password},
    );

    try {
      final token = AuthTokenResponse.fromJson(response.body);
      final user = token.toDomain();
      await _saveRefreshCredential(response.headers, requireCredential: true);
      _accessToken = token.accessToken;
      _accessTokenExpiresAt = token.expiresAt;
      _setUser(user, newSession: true);
      return user;
    } catch (error) {
      final token = _responseAccessToken(response.body);
      if (token != null) await _bestEffortLogout(token);
      await _clearLocalSession();
      if (error is ApiFailure) rethrow;
      throw ApiFailure.secureStorage();
    }
  }

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final response = await _apiClient.post(
      changePasswordPath,
      authenticated: true,
      body: {'current_password': currentPassword, 'new_password': newPassword},
    );

    try {
      final token = AuthTokenResponse.fromJson(response.body);
      final user = token.toDomain();
      await _saveRefreshCredential(response.headers, requireCredential: true);
      _accessToken = token.accessToken;
      _accessTokenExpiresAt = token.expiresAt;
      _setUser(user, newSession: true);
    } catch (error) {
      final token = _responseAccessToken(response.body);
      if (token != null) await _bestEffortLogout(token);
      await _clearLocalSession();
      if (error is ApiFailure) rethrow;
      throw ApiFailure.secureStorage();
    }
  }

  @override
  Future<void> signOut() async {
    try {
      try {
        await _beforeSignOut?.call();
      } catch (_) {
        // Device deactivation is best effort; logout must remain available.
      }
      final storedCredential = await _credentialStore.read();
      if (_accessToken == null &&
          storedCredential != null &&
          storedCredential.isNotEmpty) {
        await _refreshAccessToken();
      }

      var token = _accessToken;
      if (token != null) {
        try {
          await _sendLogout(token);
        } on ApiFailure catch (failure) {
          if (failure.isUnauthenticated && await _refreshAccessToken()) {
            token = _accessToken;
            if (token != null) await _sendLogout(token);
          }
        }
      }
    } catch (_) {
      // Local logout must remain available if Railway or the secure store is
      // temporarily unavailable.
    } finally {
      await _clearLocalSession();
    }
  }

  Future<bool> _refreshAccessToken() async {
    String? refreshCredential;
    try {
      refreshCredential = await _credentialStore.read();
    } catch (_) {
      throw ApiFailure.secureStorage();
    }

    if (refreshCredential == null || refreshCredential.isEmpty) {
      await _clearLocalSession();
      return false;
    }

    try {
      final response = await _postRefresh(refreshCredential);
      final token = AuthTokenResponse.fromJson(response.body);
      final user = token.toDomain();
      await _saveRefreshCredential(response.headers, requireCredential: false);
      _accessToken = token.accessToken;
      _accessTokenExpiresAt = token.expiresAt;
      _setUser(user);
      return true;
    } on ApiFailure catch (failure) {
      if (failure.isUnauthenticated) {
        await _clearLocalSession();
        return false;
      }
      if (failure.kind == ApiFailureKind.unknown && failure.statusCode == 200) {
        await _clearLocalSession();
      }
      rethrow;
    }
  }

  Future<ApiResponse> _postRefresh(String refreshCredential) => _apiClient.post(
    refreshPath,
    headers: {'cookie': 'aqualogic_refresh=$refreshCredential'},
  );

  Future<void> _saveRefreshCredential(
    Map<String, String> headers, {
    required bool requireCredential,
  }) async {
    final change = readRefreshCookie(headers);
    try {
      if (change.present) {
        final value = change.value;
        if (value == null) {
          await _credentialStore.delete();
          throw const ApiFailure(
            kind: ApiFailureKind.unauthenticated,
            statusCode: 401,
            message: 'The AquaLogic sign-in session is no longer active.',
          );
        }
        await _credentialStore.write(value);
        return;
      }

      if (requireCredential) {
        throw ApiFailure.secureStorage();
      }
      final existing = await _credentialStore.read();
      if (existing == null || existing.isEmpty) {
        throw ApiFailure.secureStorage();
      }
    } on ApiFailure {
      rethrow;
    } catch (_) {
      throw ApiFailure.secureStorage();
    }
  }

  Future<void> _sendLogout(String accessToken) async {
    await _apiClient.post(
      logoutPath,
      headers: {'authorization': 'Bearer $accessToken'},
    );
  }

  Future<void> _bestEffortLogout(String accessToken) async {
    try {
      await _sendLogout(accessToken);
    } catch (_) {
      // The response/session may already be invalid; never log credentials.
    }
  }

  Future<void> _clearLocalSession() async {
    _accessToken = null;
    _accessTokenExpiresAt = null;
    _currentUser = null;
    _setStatus(AuthStatus.unauthenticated);
    try {
      await _credentialStore.delete();
    } catch (_) {
      // Keep the in-memory app logged out even if platform storage reports an
      // error. The secure-store adapter itself never falls back to plaintext.
    }
  }

  void _setUser(AuthUser user, {bool newSession = false}) {
    if (newSession) _sessionGeneration++;
    _currentUser = user;
    _setStatus(
      user.mustChangePassword
          ? AuthStatus.mustChangePassword
          : AuthStatus.authenticated,
    );
  }

  void _setStatus(AuthStatus status) {
    if (_status == status) {
      notifyListeners();
      return;
    }
    _status = status;
    notifyListeners();
  }

  static String? _responseAccessToken(Object? body) {
    if (body is Map<String, dynamic>) {
      final value = body['access_token'];
      return value is String && value.isNotEmpty ? value : null;
    }
    if (body is Map) {
      final value = body['access_token'];
      return value is String && value.isNotEmpty ? value : null;
    }
    return null;
  }

  @override
  void dispose() {
    _apiClient.close();
    super.dispose();
  }
}

import 'package:aqualogic/features/auth/models/auth_user.dart';
import 'package:aqualogic/features/auth/models/user_role.dart';
import 'package:aqualogic/shared/network/api_failure.dart';

class AuthTokenResponse {
  const AuthTokenResponse({
    required this.accessToken,
    required this.expiresAt,
    required this.user,
    required this.mustChangePassword,
  });

  final String accessToken;
  final DateTime expiresAt;
  final BackendAuthUser user;
  final bool mustChangePassword;

  factory AuthTokenResponse.fromJson(Object? json) {
    final value = _object(json);
    final accessToken = value['access_token'];
    final tokenType = value['token_type'];
    final expiresAtValue = value['expires_at'];
    if (accessToken is! String ||
        accessToken.isEmpty ||
        tokenType is! String ||
        tokenType.toLowerCase() != 'bearer' ||
        expiresAtValue is! String) {
      throw _invalidResponse();
    }

    final expiresAt = DateTime.tryParse(expiresAtValue);
    if (expiresAt == null) throw _invalidResponse();

    return AuthTokenResponse(
      accessToken: accessToken,
      expiresAt: expiresAt.toUtc(),
      user: BackendAuthUser.fromJson(value['user']),
      mustChangePassword: value['must_change_password'] == true,
    );
  }

  AuthUser toDomain() => user.toDomain(
    mustChangePassword: mustChangePassword || user.mustChangePassword,
  );
}

class BackendAuthUser {
  const BackendAuthUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.isActive,
    required this.mustChangePassword,
  });

  final int id;
  final String name;
  final String email;
  final UserRole role;
  final bool isActive;
  final bool mustChangePassword;

  factory BackendAuthUser.fromJson(Object? json) {
    final value = _object(json);
    final rawId = value['id'];
    final rawName = value['name'];
    final rawEmail = value['email'];
    final rawRole = value['role'];
    final rawActive = value['is_active'];
    final id = rawId is int ? rawId : (rawId is num ? rawId.toInt() : null);

    if (id == null ||
        rawName is! String ||
        rawName.isEmpty ||
        rawEmail is! String ||
        rawEmail.isEmpty ||
        rawRole is! String ||
        rawActive is! bool) {
      throw _invalidResponse();
    }
    if (!rawActive) {
      throw const ApiFailure(
        kind: ApiFailureKind.unauthenticated,
        statusCode: 401,
        message: 'This AquaLogic account is inactive.',
      );
    }

    final role = switch (rawRole) {
      'admin' => UserRole.admin,
      'staff' => UserRole.staff,
      _ => throw const ApiFailure(
        kind: ApiFailureKind.unknown,
        statusCode: 200,
        message: 'This account cannot be used in the mobile app.',
      ),
    };

    return BackendAuthUser(
      id: id,
      name: rawName,
      email: rawEmail,
      role: role,
      isActive: rawActive,
      mustChangePassword: value['must_change_password'] == true,
    );
  }

  factory BackendAuthUser.fromMeJson(Object? json) =>
      BackendAuthUser.fromJson(json);

  AuthUser toDomain({bool? mustChangePassword}) => AuthUser(
    id: id.toString(),
    name: name,
    email: email,
    role: role,
    isActive: isActive,
    mustChangePassword: mustChangePassword ?? this.mustChangePassword,
  );
}

Map<String, dynamic> _object(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.cast<String, dynamic>();
  throw _invalidResponse();
}

ApiFailure _invalidResponse() => const ApiFailure(
  kind: ApiFailureKind.unknown,
  message: 'AquaLogic returned an invalid sign-in response.',
);

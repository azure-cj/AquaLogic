import 'package:aqualogic/features/auth/models/user_role.dart';

class AuthUser {
  const AuthUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
  });

  final String id;
  final String name;
  final String email;
  final UserRole role;

  String get roleLabel => role.displayLabel;
}

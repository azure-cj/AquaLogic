import 'package:flutter/foundation.dart';

import 'package:aqualogic/features/auth/models/auth_user.dart';
import 'package:aqualogic/features/auth/models/user_role.dart';

enum AuthStatus {
  checking,
  unauthenticated,
  authenticated,
  mustChangePassword,
  connectionUnavailable,
}

/// The small auth boundary used by the app shell.
///
/// A future API-backed repository can provide the same state and operations
/// without requiring the login or navigation widgets to change.
abstract class AuthService extends ChangeNotifier {
  AuthStatus get status;
  AuthUser? get currentUser;

  /// Changes only when a new backend session is established, not on refresh.
  int get sessionGeneration => 0;

  /// Called once by app composition. Local/test services can keep the default.
  Future<void> initialize() async {}

  Future<AuthUser?> signIn({required String email, required String password});

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    throw UnsupportedError('Password changes are not available.');
  }

  Future<void> signOut();
}

/// Local-only prototype authentication data.
///
/// These accounts deliberately live outside the LoginScreen so replacing this
/// service with a real repository does not require changing the form UI.
class MockAuthAccount {
  const MockAuthAccount({
    required this.id,
    required this.email,
    required this.password,
    required this.name,
    required this.role,
  });

  final String id;
  final String email;
  final String password;
  final String name;
  final UserRole role;

  AuthUser toUser() {
    return AuthUser(id: id, name: name, email: email, role: role);
  }
}

class MockAuthService extends AuthService {
  /// Development-only accounts. They are not production credentials.
  static const demoAccounts = <MockAuthAccount>[
    MockAuthAccount(
      id: 'mock-owner',
      email: 'owner@aqualogic.local',
      password: 'owner123',
      name: 'JRed Owner',
      role: UserRole.admin,
    ),
    MockAuthAccount(
      id: 'mock-staff',
      email: 'staff@aqualogic.local',
      password: 'staff123',
      name: 'AquaLogic Staff',
      role: UserRole.staff,
    ),
  ];

  AuthStatus _status = AuthStatus.unauthenticated;
  AuthUser? _currentUser;

  @override
  AuthStatus get status => _status;

  @override
  AuthUser? get currentUser => _currentUser;

  @override
  Future<AuthUser?> signIn({
    required String email,
    required String password,
  }) async {
    // Keep the async boundary in place so the future API implementation has
    // the same contract and the UI can exercise its loading state.
    await Future<void>.delayed(const Duration(milliseconds: 220));

    final normalizedEmail = email.trim().toLowerCase();
    MockAuthAccount? matchingAccount;
    for (final account in demoAccounts) {
      if (account.email.toLowerCase() == normalizedEmail &&
          account.password == password) {
        matchingAccount = account;
        break;
      }
    }

    if (matchingAccount == null) return null;

    _currentUser = matchingAccount.toUser();
    _status = AuthStatus.authenticated;
    notifyListeners();
    return _currentUser;
  }

  @override
  Future<void> signOut() async {
    if (_currentUser == null && _status == AuthStatus.unauthenticated) {
      return;
    }

    _currentUser = null;
    _status = AuthStatus.unauthenticated;
    notifyListeners();
  }
}

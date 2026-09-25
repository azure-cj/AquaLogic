import 'package:flutter/material.dart';

import 'package:aqualogic/app/auth/auth_scope.dart';
import 'package:aqualogic/app/home/home_repository_scope.dart';
import 'package:aqualogic/app/navigation/aqualogic_shell.dart';
import 'package:aqualogic/app/tanks/tank_repository_scope.dart';
import 'package:aqualogic/features/home/data/mock_home_repository.dart';
import 'package:aqualogic/features/tanks/data/mock_tank_repository.dart';

/// Shared authenticated composition point for future role-specific shells.
///
/// The user role comes from authentication state; it is never selected by a
/// presentation widget or inferred from the submitted credentials.
class AuthenticatedShell extends StatelessWidget {
  const AuthenticatedShell({super.key});

  @override
  Widget build(BuildContext context) {
    final user = AuthScope.of(context).currentUser;
    if (user == null) return const SizedBox.shrink();

    return AquaLogicShell(
      user: user,
      homeRepository:
          HomeRepositoryScope.maybeOf(context) ?? const MockHomeRepository(),
      tankRepository:
          TankRepositoryScope.maybeOf(context) ?? const MockTankRepository(),
    );
  }
}

import 'package:flutter/material.dart';

import 'package:aqualogic/app/auth/auth_scope.dart';
import 'package:aqualogic/app/navigation/authenticated_shell.dart';
import 'package:aqualogic/app/theme/app_colors.dart';
import 'package:aqualogic/features/auth/data/mock_auth_service.dart';
import 'package:aqualogic/features/auth/screens/login_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = AuthScope.of(context);
    final child = switch (authService.status) {
      AuthStatus.checking => const _AuthChecking(),
      AuthStatus.unauthenticated => const LoginScreen(),
      AuthStatus.authenticated => const AuthenticatedShell(),
    };

    final stateKey = switch (authService.status) {
      AuthStatus.checking => 'auth-checking',
      AuthStatus.unauthenticated => 'auth-login',
      AuthStatus.authenticated =>
        'auth-${authService.currentUser?.id ?? 'unknown'}',
    };

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          alignment: Alignment.topCenter,
          children: <Widget>[...previousChildren, ?currentChild],
        );
      },
      child: KeyedSubtree(key: ValueKey(stateKey), child: child),
    );
  }
}

class _AuthChecking extends StatelessWidget {
  const _AuthChecking();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.background,
      body: Center(child: CircularProgressIndicator(color: AppColors.tealDark)),
    );
  }
}

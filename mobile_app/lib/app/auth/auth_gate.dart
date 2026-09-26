import 'package:flutter/material.dart';

import 'package:aqualogic/app/auth/auth_scope.dart';
import 'package:aqualogic/app/navigation/authenticated_shell.dart';
import 'package:aqualogic/app/navigation/aqualogic_shell.dart';
import 'package:aqualogic/app/theme/app_colors.dart';
import 'package:aqualogic/features/auth/data/mock_auth_service.dart';
import 'package:aqualogic/features/auth/screens/login_screen.dart';
import 'package:aqualogic/features/auth/screens/password_change_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({
    super.key,
    this.animateInitialState = true,
    this.onAuthenticatedShellReady,
  });

  /// Lets a covering startup screen own the first visible transition.
  ///
  /// State changes after the first frame keep the normal AuthGate animation.
  final bool animateInitialState;
  final ValueChanged<AquaLogicShellState>? onAuthenticatedShellReady;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  var _hasBuilt = false;

  @override
  Widget build(BuildContext context) {
    final authService = AuthScope.of(context);
    final authenticatedUserId = authService.currentUser?.id;
    final child = switch (authService.status) {
      AuthStatus.checking => const _AuthChecking(),
      AuthStatus.unauthenticated => const LoginScreen(),
      AuthStatus.authenticated => AuthenticatedShell(
        onReady: (shell) {
          if (authService.status != AuthStatus.authenticated ||
              authService.currentUser?.id != authenticatedUserId ||
              shell.widget.user.id != authenticatedUserId) {
            return;
          }
          widget.onAuthenticatedShellReady?.call(shell);
        },
      ),
      AuthStatus.mustChangePassword => const PasswordChangeScreen(),
      AuthStatus.connectionUnavailable => const _AuthUnavailable(),
    };

    final stateKey = switch (authService.status) {
      AuthStatus.checking => 'auth-checking',
      AuthStatus.unauthenticated => 'auth-login',
      AuthStatus.mustChangePassword =>
        'auth-password-change-${authService.currentUser?.id ?? 'unknown'}',
      AuthStatus.connectionUnavailable => 'auth-unavailable',
      AuthStatus.authenticated =>
        'auth-${authService.currentUser?.id ?? 'unknown'}',
    };

    final duration = !_hasBuilt && !widget.animateInitialState
        ? Duration.zero
        : const Duration(milliseconds: 280);
    _hasBuilt = true;

    return AnimatedSwitcher(
      duration: duration,
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

class _AuthUnavailable extends StatelessWidget {
  const _AuthUnavailable();

  @override
  Widget build(BuildContext context) {
    final authService = AuthScope.of(context);
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.cloud_off_outlined,
                    color: AppColors.tealDark,
                    size: 34,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "Couldn't connect to AquaLogic",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Check your connection and retry. Any saved sign-in has been kept on this device.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.muted,
                      fontSize: 13,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    key: const ValueKey('auth-startup-retry'),
                    onPressed: () => authService.initialize(),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Retry'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.tealDark,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import 'package:aqualogic/app/auth/auth_scope.dart';
import 'package:aqualogic/app/navigation/authenticated_shell.dart';
import 'package:aqualogic/app/theme/app_colors.dart';
import 'package:aqualogic/features/auth/data/mock_auth_service.dart';
import 'package:aqualogic/features/auth/screens/login_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key, this.animateInitialState = true});

  /// Lets a covering startup screen own the first visible transition.
  ///
  /// State changes after the first frame keep the normal AuthGate animation.
  final bool animateInitialState;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  var _hasBuilt = false;

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

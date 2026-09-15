import 'package:flutter/material.dart';

import 'package:aqualogic/features/auth/data/mock_auth_service.dart';

class AuthScope extends InheritedNotifier<AuthService> {
  const AuthScope({
    super.key,
    required AuthService authService,
    required super.child,
  }) : _authService = authService,
       super(notifier: authService);

  final AuthService _authService;

  static AuthService of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AuthScope>();
    assert(scope != null, 'AuthScope is missing above this context.');
    return scope!._authService;
  }
}

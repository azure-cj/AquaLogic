import 'dart:async';

import 'package:aqualogic/app/auth/auth_scope.dart';
import 'package:aqualogic/app/startup/splash_screen.dart';
import 'package:aqualogic/app/theme/app_colors.dart';
import 'package:aqualogic/features/auth/data/api_auth_service.dart';
import 'package:aqualogic/features/auth/data/mock_auth_service.dart';
import 'package:flutter/material.dart';

const _startupPreview = bool.fromEnvironment('AQUALOGIC_STARTUP_PREVIEW');

class AquaLogicApp extends StatefulWidget {
  const AquaLogicApp({super.key, this.authService});

  final AuthService? authService;

  @override
  State<AquaLogicApp> createState() => _AquaLogicAppState();
}

class _AquaLogicAppState extends State<AquaLogicApp> {
  late final AuthService _authService;
  late final bool _ownsAuthService;

  @override
  void initState() {
    super.initState();
    _ownsAuthService = widget.authService == null;
    _authService = widget.authService ?? ApiAuthService();
    unawaited(_authService.initialize());
  }

  @override
  void dispose() {
    if (_ownsAuthService) _authService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AquaLogic',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme:
            ColorScheme.fromSeed(
              seedColor: AppColors.teal,
              brightness: Brightness.light,
            ).copyWith(
              primary: AppColors.tealDark,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: AppColors.text,
              outline: AppColors.line,
            ),
        fontFamily: 'Geist',
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.line),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.tealDark, width: 1.5),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 13,
          ),
        ),
      ),
      home: AuthScope(
        authService: _authService,
        child: const SplashScreen(
          minimumDisplayDuration: _startupPreview
              ? Duration(seconds: 6)
              : Duration(milliseconds: 600),
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:aqualogic/app/auth/auth_scope.dart';
import 'package:aqualogic/app/alerts/alert_repository_scope.dart';
import 'package:aqualogic/app/control/equipment_repository_scope.dart';
import 'package:aqualogic/app/fish/fish_repository_scope.dart';
import 'package:aqualogic/app/home/home_repository_scope.dart';
import 'package:aqualogic/app/tanks/tank_repository_scope.dart';
import 'package:aqualogic/app/startup/splash_screen.dart';
import 'package:aqualogic/app/theme/app_colors.dart';
import 'package:aqualogic/features/auth/data/api_auth_service.dart';
import 'package:aqualogic/features/auth/data/mock_auth_service.dart';
import 'package:aqualogic/features/alerts/data/api_alert_repository.dart';
import 'package:aqualogic/features/alerts/data/mock_alert_repository.dart';
import 'package:aqualogic/features/control/data/api_equipment_repository.dart';
import 'package:aqualogic/features/control/data/mock_equipment_repository.dart';
import 'package:aqualogic/features/fish/data/api_fish_repository.dart';
import 'package:aqualogic/features/fish/data/mock_fish_repository.dart';
import 'package:aqualogic/features/home/data/api_home_repository.dart';
import 'package:aqualogic/features/home/data/home_repository.dart';
import 'package:aqualogic/features/home/data/mock_home_repository.dart';
import 'package:aqualogic/features/push_notifications/data/push_notification_service.dart';
import 'package:aqualogic/features/tanks/data/api_tank_repository.dart';
import 'package:aqualogic/features/tanks/data/mock_tank_repository.dart';
import 'package:flutter/material.dart';

const _startupPreview = bool.fromEnvironment('AQUALOGIC_STARTUP_PREVIEW');

class AquaLogicApp extends StatefulWidget {
  const AquaLogicApp({
    super.key,
    this.authService,
    this.homeRepository,
    this.tankRepository,
    this.alertRepository,
    this.fishRepository,
    this.equipmentRepository,
    this.pushNotificationService,
  });

  final AuthService? authService;
  final HomeRepository? homeRepository;
  final TankRepository? tankRepository;
  final AlertRepository? alertRepository;
  final FishRepository? fishRepository;
  final EquipmentRepository? equipmentRepository;
  final PushNotificationService? pushNotificationService;

  @override
  State<AquaLogicApp> createState() => _AquaLogicAppState();
}

class _AquaLogicAppState extends State<AquaLogicApp> {
  late final AuthService _authService;
  late final bool _ownsAuthService;
  late final HomeRepository _homeRepository;
  late final TankRepository _tankRepository;
  late final AlertRepository _alertRepository;
  late final FishRepository _fishRepository;
  late final EquipmentRepository _equipmentRepository;

  @override
  void initState() {
    super.initState();
    _ownsAuthService = widget.authService == null;
    _authService = widget.authService ?? ApiAuthService();
    _homeRepository =
        widget.homeRepository ??
        switch (_authService) {
          ApiAuthService apiAuthService => ApiHomeRepository(
            apiClient: apiAuthService.apiClient,
          ),
          _ => const MockHomeRepository(),
        };
    _tankRepository =
        widget.tankRepository ??
        switch (_authService) {
          ApiAuthService apiAuthService => ApiTankRepository(
            apiClient: apiAuthService.apiClient,
          ),
          _ => const MockTankRepository(),
        };
    _alertRepository =
        widget.alertRepository ??
        switch (_authService) {
          ApiAuthService apiAuthService => ApiAlertRepository(
            apiClient: apiAuthService.apiClient,
          ),
          _ => const MockAlertRepository(),
        };
    _fishRepository =
        widget.fishRepository ??
        switch (_authService) {
          ApiAuthService apiAuthService => ApiFishRepository(
            apiClient: apiAuthService.apiClient,
          ),
          _ => const MockFishRepository(),
        };
    _equipmentRepository =
        widget.equipmentRepository ??
        switch (_authService) {
          ApiAuthService apiAuthService => ApiEquipmentRepository(
            apiClient: apiAuthService.apiClient,
          ),
          _ => const MockEquipmentRepository(),
        };
    unawaited(_authService.initialize());
    final pushNotificationService = widget.pushNotificationService;
    if (pushNotificationService != null) {
      unawaited(pushNotificationService.initialize());
    }
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
        child: HomeRepositoryScope(
          repository: _homeRepository,
          child: TankRepositoryScope(
            repository: _tankRepository,
            child: AlertRepositoryScope(
              repository: _alertRepository,
              child: FishRepositoryScope(
                repository: _fishRepository,
                child: EquipmentRepositoryScope(
                  repository: _equipmentRepository,
                  child: const SplashScreen(
                    minimumDisplayDuration: _startupPreview
                        ? Duration(seconds: 6)
                        : Duration(milliseconds: 600),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

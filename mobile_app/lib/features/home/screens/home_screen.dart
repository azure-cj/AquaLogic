import 'dart:async';

import 'package:aqualogic/app/theme/app_tokens.dart';
import 'package:aqualogic/features/auth/models/auth_user.dart';
import 'package:aqualogic/features/auth/models/user_role.dart';
import 'package:aqualogic/features/home/data/home_repository.dart';
import 'package:aqualogic/features/home/data/mock_home_repository.dart';
import 'package:aqualogic/features/home/models/home_dashboard_data.dart';
import 'package:aqualogic/features/home/widgets/home_async_states.dart';
import 'package:aqualogic/features/home/widgets/home_shared_widgets.dart';
import 'package:aqualogic/features/home/widgets/owner_home_content.dart';
import 'package:aqualogic/features/home/widgets/staff_home_content.dart';
import 'package:aqualogic/shared/network/api_failure.dart';
import 'package:aqualogic/shared/widgets/app_page.dart';
import 'package:flutter/material.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.user,
    required this.onOpenAlerts,
    required this.onOpenTanks,
    this.onOpenAlert,
    this.onOpenTank,
    this.repository = const MockHomeRepository(),
  });

  final AuthUser user;
  final VoidCallback onOpenAlerts;
  final VoidCallback onOpenTanks;
  final ValueChanged<HomeAttentionItem>? onOpenAlert;
  final ValueChanged<HomeTankSummary>? onOpenTank;
  final HomeRepository repository;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  static const _foregroundRefreshInterval = Duration(minutes: 1);

  HomeDashboardData? _data;
  ApiFailure? _initialFailure;
  ApiFailure? _refreshFailure;
  bool _loading = true;
  bool? _apiAvailable;
  DateTime? _lastSuccessfulLoadAt;
  Future<void>? _loadInFlight;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.repository, widget.repository)) {
      unawaited(_load());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final lastSuccess = _lastSuccessfulLoadAt;
    if (_data == null ||
        lastSuccess == null ||
        DateTime.now().toUtc().difference(lastSuccess) >=
            _foregroundRefreshInterval) {
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _load() {
    final inFlight = _loadInFlight;
    if (inFlight != null) return inFlight;

    final request = _loadDashboard();
    _loadInFlight = request;
    return request.whenComplete(() {
      if (identical(_loadInFlight, request)) _loadInFlight = null;
    });
  }

  Future<void> _loadDashboard() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _initialFailure = null;
      });
    }
    try {
      final data = await widget.repository.load();
      if (!mounted) return;
      setState(() {
        _data = data;
        _lastSuccessfulLoadAt = data.loadedAt ?? DateTime.now().toUtc();
        _apiAvailable = true;
        _initialFailure = null;
        _refreshFailure = null;
      });
    } catch (error) {
      if (!mounted) return;
      final failure = error is ApiFailure
          ? error
          : const ApiFailure(
              kind: ApiFailureKind.unknown,
              message: 'AquaLogic Home data could not be loaded. Try again.',
              retryable: true,
            );
      setState(() {
        _apiAvailable = false;
        if (_data == null) {
          _initialFailure = failure;
        } else {
          _refreshFailure = failure;
        }
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final isOwner = widget.user.role == UserRole.admin;
    final content = data == null
        ? _unloadedContent()
        : switch (widget.user.role) {
            UserRole.admin => OwnerHomeContent(
              data: data,
              isLiveData: data.isLiveData,
              onOpenAlerts: widget.onOpenAlerts,
              onOpenTanks: widget.onOpenTanks,
              onOpenAlert: widget.onOpenAlert,
              onOpenTank: widget.onOpenTank,
            ),
            UserRole.staff => StaffHomeContent(
              data: data,
              isLiveData: data.isLiveData,
              onOpenAlerts: widget.onOpenAlerts,
              onOpenTanks: widget.onOpenTanks,
              onOpenTank: widget.onOpenTank,
              onOpenAlert: widget.onOpenAlert,
            ),
          };

    final children = <Widget>[];
    if (_refreshFailure != null) {
      children.add(HomeStaleDataCard(onRetry: () => unawaited(_load())));
    }
    if (data != null && data.hasPartialFailure) {
      children.add(
        HomePartialFailureCard(
          alertsAvailable: data.alertsAvailable,
          monitoringAvailable: data.monitoringIncidentsAvailable,
          onRetry: () => unawaited(_load()),
        ),
      );
    }
    children.add(content);

    return AppPage(
      bottomClearance: AppSpacing.bottomDockClearance,
      onRefresh: _load,
      header: HomeHero(
        user: widget.user,
        isOnline: _apiAvailable,
        data: data,
        isLoading: data == null && _loading,
        showFleetStatus: isOwner,
      ),
      children: children,
    );
  }

  Widget _unloadedContent() {
    if (_loading) return const HomeLoadingContent();
    final failure = _initialFailure;
    return HomeErrorCard(
      message: failure?.message ?? 'Check your connection and try again.',
      retrying: _loading,
      onRetry: () => unawaited(_load()),
    );
  }
}

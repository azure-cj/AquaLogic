import 'dart:async';

import 'package:aqualogic/app/theme/app_colors.dart';
import 'package:aqualogic/app/theme/app_tokens.dart';
import 'package:aqualogic/features/auth/models/auth_user.dart';
import 'package:aqualogic/features/sensors/models/sensor_snapshot.dart';
import 'package:aqualogic/features/tanks/data/mock_tank_repository.dart';
import 'package:aqualogic/features/tanks/models/tank_info.dart';
import 'package:aqualogic/features/tanks/screens/tank_detail_screen.dart';
import 'package:aqualogic/features/tanks/widgets/tank_overview_card.dart';
import 'package:aqualogic/shared/network/api_failure.dart';
import 'package:aqualogic/shared/models/aqualogic_status.dart';
import 'package:aqualogic/shared/widgets/app_page.dart';
import 'package:aqualogic/shared/widgets/semantic_status_widgets.dart';
import 'package:aqualogic/shared/widgets/soft_card.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

enum TankFilter { all, needsAttention, offline }

class TanksScreen extends StatefulWidget {
  const TanksScreen({
    super.key,
    required this.snapshot,
    this.user,
    this.repository,
    this.onOpenIssue,
  });

  final SensorSnapshot snapshot;
  final AuthUser? user;
  final TankRepository? repository;
  final Future<void> Function(TankIssue issue)? onOpenIssue;

  @override
  State<TanksScreen> createState() => _TanksScreenState();
}

class _TanksScreenState extends State<TanksScreen> with WidgetsBindingObserver {
  static const _foregroundRefreshInterval = Duration(minutes: 1);

  TankRepository get _repository =>
      widget.repository ?? const MockTankRepository();

  List<TankInfo>? _tanks;
  ApiFailure? _initialFailure;
  ApiFailure? _refreshFailure;
  bool _loading = true;
  DateTime? _lastSuccessfulLoadAt;
  Future<void>? _loadInFlight;
  var _query = '';
  var _filter = TankFilter.all;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant TanksScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.repository, widget.repository)) {
      _tanks = null;
      unawaited(_load());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final lastSuccess = _lastSuccessfulLoadAt;
    if (_tanks == null ||
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
    final request = _loadTanks();
    _loadInFlight = request;
    return request.whenComplete(() {
      if (identical(_loadInFlight, request)) _loadInFlight = null;
    });
  }

  Future<void> _loadTanks() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _initialFailure = null;
      });
    }
    try {
      final tanks = await _repository.loadTanks(snapshot: widget.snapshot);
      if (!mounted) return;
      setState(() {
        _tanks = tanks;
        _lastSuccessfulLoadAt = DateTime.now().toUtc();
        _initialFailure = null;
        _refreshFailure = null;
      });
    } catch (error) {
      if (!mounted) return;
      final failure = error is ApiFailure
          ? error
          : const ApiFailure(
              kind: ApiFailureKind.unknown,
              message: 'Tank data could not be loaded. Try again.',
              retryable: true,
            );
      setState(() {
        if (_tanks == null) {
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
    final allTanks = _tanks;
    final tanks = allTanks == null
        ? const <TankInfo>[]
        : _visibleTanks(allTanks);
    final totalTanks = allTanks?.length ?? 0;
    final attentionCount = allTanks?.where(_needsAttention).length ?? 0;
    final offlineCount = allTanks?.where(_isOffline).length ?? 0;

    return AppPage(
      bottomClearance: AppSpacing.bottomDockClearance,
      onRefresh: _load,
      header: _TanksHeader(
        onQueryChanged: (value) => setState(() => _query = value),
      ),
      children: [
        if (allTanks == null)
          _loading
              ? const _TanksLoadingState()
              : _TanksErrorCard(
                  message:
                      _initialFailure?.message ??
                      'Check your connection and retry.',
                  retrying: _loading,
                  onRetry: () => unawaited(_load()),
                )
        else ...[
          if (_refreshFailure != null)
            _TanksStaleCard(
              message: _refreshFailure!.message,
              onRetry: () => unawaited(_load()),
            ),
          _FleetSummary(
            totalCount: totalTanks,
            attentionCount: attentionCount,
            offlineCount: offlineCount,
          ),
          _TankFilters(
            selected: _filter,
            totalCount: totalTanks,
            attentionCount: attentionCount,
            offlineCount: offlineCount,
            onSelected: (filter) => setState(() => _filter = filter),
          ),
          if (allTanks.isEmpty)
            EmptyState(
              title: 'No active tanks',
              message:
                  'AquaLogic currently has no active tanks for this account.',
              icon: LucideIcons.searchX,
            )
          else if (tanks.isEmpty)
            EmptyState(
              title: _emptyTitle,
              message: _emptyMessage,
              icon: _filter == TankFilter.all
                  ? LucideIcons.searchX
                  : LucideIcons.filterX,
            )
          else
            ...tanks.map(
              (tank) => TankOverviewCard(
                tank: tank,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => _repository.isLiveData
                          ? TankDetailPage(
                              tankId: tank.tankId,
                              repository: _repository,
                              snapshot: widget.snapshot,
                              user: widget.user,
                              onOpenIssue: widget.onOpenIssue,
                            )
                          : TankDetailScreen(
                              tank: tank,
                              snapshot: widget.snapshot,
                              user: widget.user,
                            ),
                    ),
                  );
                },
              ),
            ),
        ],
      ],
    );
  }

  String get _emptyTitle {
    if (_query.trim().isNotEmpty) return 'No tanks match this search';
    return switch (_filter) {
      TankFilter.all => 'No tanks match this search',
      TankFilter.needsAttention => 'No tanks need attention',
      TankFilter.offline => 'No tanks are offline',
    };
  }

  String get _emptyMessage {
    if (_query.trim().isNotEmpty) return 'Try another tank name or location.';
    return switch (_filter) {
      TankFilter.all => 'Monitored tanks will appear here when available.',
      TankFilter.needsAttention => 'All monitored tanks are currently clear.',
      TankFilter.offline => 'All monitored tanks are reporting normally.',
    };
  }

  List<TankInfo> _visibleTanks(List<TankInfo> tanks) {
    final query = _query.trim().toLowerCase();
    return tanks
        .where((tank) {
          final matchesQuery =
              query.isEmpty ||
              tank.name.toLowerCase().contains(query) ||
              tank.subtitle.toLowerCase().contains(query) ||
              tank.locationOrType.toLowerCase().contains(query);
          final matchesFilter = switch (_filter) {
            TankFilter.all => true,
            TankFilter.needsAttention => _needsAttention(tank),
            TankFilter.offline => _isOffline(tank),
          };
          return matchesQuery && matchesFilter;
        })
        .toList(growable: false);
  }

  bool _needsAttention(TankInfo tank) {
    if (tank.isRetired) return false;
    return tank.operationalStatus == OperationalStatus.warning ||
        tank.operationalStatus == OperationalStatus.critical;
  }

  bool _isOffline(TankInfo tank) {
    return !tank.isRetired &&
        tank.operationalStatus == OperationalStatus.offline;
  }
}

class _TanksLoadingState extends StatelessWidget {
  const _TanksLoadingState();

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      key: const ValueKey('tanks-loading-content'),
      label: 'Loading live tank directory',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SoftCard(
            child: Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.tealDark,
                    value: reduceMotion ? 0.65 : null,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Loading tanks from AquaLogic',
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sectionGap),
          for (var index = 0; index < 2; index++) ...[
            const _TankCardPlaceholder(),
            if (index == 0) const SizedBox(height: AppSpacing.sectionGap),
          ],
        ],
      ),
    );
  }
}

class _TankCardPlaceholder extends StatelessWidget {
  const _TankCardPlaceholder();

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 12,
            width: 155,
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            height: 9,
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.background.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(5),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            height: 9,
            width: 190,
            decoration: BoxDecoration(
              color: AppColors.background.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(5),
            ),
          ),
        ],
      ),
    );
  }
}

class _TanksErrorCard extends StatelessWidget {
  const _TanksErrorCard({
    required this.message,
    required this.retrying,
    required this.onRetry,
  });

  final String message;
  final bool retrying;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return SoftCard(
      child: Column(
        key: const ValueKey('tanks-load-error'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(LucideIcons.wifiOff, color: AppColors.offline, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Couldn't load Tanks from AquaLogic",
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '$message Tank status has not been changed by this phone connection failure.',
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 12,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              key: const ValueKey('tanks-load-retry'),
              onPressed: retrying ? null : onRetry,
              icon: retrying
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        value: reduceMotion ? 0.65 : null,
                      ),
                    )
                  : const Icon(LucideIcons.refreshCw, size: 16),
              label: Text(retrying ? 'Retrying' : 'Retry'),
              style: TextButton.styleFrom(foregroundColor: AppColors.tealDark),
            ),
          ),
        ],
      ),
    );
  }
}

class _TanksStaleCard extends StatelessWidget {
  const _TanksStaleCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(LucideIcons.wifiOff, color: AppColors.offline, size: 19),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              "Couldn't refresh the tank directory. Showing the last successful list. $message",
              style: const TextStyle(
                color: AppColors.text,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(width: 4),
          TextButton(
            key: const ValueKey('tanks-stale-retry'),
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class _TanksHeader extends StatelessWidget {
  const _TanksHeader({required this.onQueryChanged});

  final ValueChanged<String> onQueryChanged;

  @override
  Widget build(BuildContext context) {
    final safeTop = MediaQuery.paddingOf(context).top;

    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        Positioned(
          right: -135,
          bottom: 0,
          width: 560,
          height: 208,
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: Opacity(
                opacity: 0.72,
                child: Image.asset(
                  'assets/images/tank_header.png',
                  fit: BoxFit.cover,
                  alignment: Alignment.centerRight,
                ),
              ),
            ),
          ),
        ),
        Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(
            AppSpacing.pageGutter,
            safeTop + 18,
            AppSpacing.pageGutter,
            20,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.56),
                AppColors.background.withValues(alpha: 0.82),
              ],
            ),
            border: Border(
              bottom: BorderSide(color: AppColors.line.withValues(alpha: 0.72)),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Tanks',
                key: ValueKey('tanks-page-title'),
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 28,
                  height: 1.05,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 5),
              const Text(
                'Monitor your aquarium fleet',
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 17),
              TextField(
                onChanged: onQueryChanged,
                textInputAction: TextInputAction.search,
                keyboardType: TextInputType.text,
                style: const TextStyle(
                  color: AppColors.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
                decoration: InputDecoration(
                  hintText: 'Search tanks...',
                  hintStyle: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                  ),
                  prefixIcon: const Icon(
                    LucideIcons.search,
                    color: AppColors.tealDark,
                    size: 20,
                  ),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.94),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 13,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: AppColors.line),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: AppColors.line),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(
                      color: AppColors.tealDark,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FleetSummary extends StatelessWidget {
  const _FleetSummary({
    required this.totalCount,
    required this.attentionCount,
    required this.offlineCount,
  });

  final int totalCount;
  final int attentionCount;
  final int offlineCount;

  @override
  Widget build(BuildContext context) {
    final tankWord = totalCount == 1 ? 'tank' : 'tanks';
    final summary = attentionCount > 0
        ? '$totalCount $tankWord · $attentionCount need attention'
        : offlineCount > 0
        ? '$totalCount $tankWord · $offlineCount offline'
        : '$totalCount $tankWord · All in range';

    return Semantics(
      container: true,
      label: summary,
      child: Text(
        summary,
        style: const TextStyle(
          color: AppColors.text,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _TankFilters extends StatelessWidget {
  const _TankFilters({
    required this.selected,
    required this.totalCount,
    required this.attentionCount,
    required this.offlineCount,
    required this.onSelected,
  });

  final TankFilter selected;
  final int totalCount;
  final int attentionCount;
  final int offlineCount;
  final ValueChanged<TankFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: [
          _FilterChip(
            key: const ValueKey('tank-filter-all'),
            label: 'All',
            count: totalCount,
            icon: LucideIcons.layoutGrid,
            selected: selected == TankFilter.all,
            onTap: () => onSelected(TankFilter.all),
          ),
          const SizedBox(width: 8),
          _FilterChip(
            key: const ValueKey('tank-filter-attention'),
            label: 'Attention',
            count: attentionCount,
            icon: LucideIcons.triangleAlert,
            selected: selected == TankFilter.needsAttention,
            onTap: () => onSelected(TankFilter.needsAttention),
          ),
          const SizedBox(width: 8),
          _FilterChip(
            key: const ValueKey('tank-filter-offline'),
            label: 'Offline',
            count: offlineCount,
            icon: LucideIcons.wifiOff,
            selected: selected == TankFilter.offline,
            onTap: () => onSelected(TankFilter.offline),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    super.key,
    required this.label,
    required this.count,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? AppColors.tealDark : AppColors.text;
    return Semantics(
      button: true,
      selected: selected,
      onTap: onTap,
      label: 'Show $label tanks, $count',
      child: ExcludeSemantics(
        child: Material(
          color: selected
              ? AppColors.mint
              : Colors.white.withValues(alpha: 0.9),
          shape: RoundedRectangleBorder(
            side: BorderSide(
              color: selected
                  ? AppColors.teal.withValues(alpha: 0.55)
                  : AppColors.line,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 17, color: foreground),
                    const SizedBox(width: 7),
                    Text(
                      label,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 12,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      constraints: const BoxConstraints(minWidth: 24),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 4,
                      ),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected
                            ? Colors.white.withValues(alpha: 0.48)
                            : AppColors.background,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        '$count',
                        style: TextStyle(
                          color: foreground,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

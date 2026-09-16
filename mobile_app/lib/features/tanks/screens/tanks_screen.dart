import 'package:aqualogic/app/theme/app_colors.dart';
import 'package:aqualogic/features/auth/models/auth_user.dart';
import 'package:aqualogic/features/sensors/models/sensor_snapshot.dart';
import 'package:aqualogic/features/tanks/data/mock_tank_repository.dart';
import 'package:aqualogic/features/tanks/models/tank_info.dart';
import 'package:aqualogic/features/tanks/screens/tank_detail_screen.dart';
import 'package:aqualogic/features/tanks/widgets/tank_overview_card.dart';
import 'package:aqualogic/shared/models/aqualogic_status.dart';
import 'package:aqualogic/shared/widgets/app_page.dart';
import 'package:aqualogic/shared/widgets/semantic_status_widgets.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

enum TankFilter { all, needsAttention, offline }

class TanksScreen extends StatefulWidget {
  const TanksScreen({
    super.key,
    required this.snapshot,
    this.user,
    this.repository,
  });

  final SensorSnapshot snapshot;
  final AuthUser? user;
  final TankRepository? repository;

  @override
  State<TanksScreen> createState() => _TanksScreenState();
}

class _TanksScreenState extends State<TanksScreen> {
  late final TankRepository _repository =
      widget.repository ?? const MockTankRepository();
  var _query = '';
  var _filter = TankFilter.all;

  @override
  Widget build(BuildContext context) {
    final allTanks = _repository.list(snapshot: widget.snapshot);
    final tanks = _visibleTanks(allTanks);
    final attentionCount = allTanks.where(_needsAttention).length;
    final offlineCount = allTanks.where(_isOffline).length;

    return AppPage(
      header: _TanksHeader(
        onQueryChanged: (value) => setState(() => _query = value),
      ),
      children: [
        _FleetSummary(
          totalCount: allTanks.length,
          attentionCount: attentionCount,
          offlineCount: offlineCount,
        ),
        _TankFilters(
          selected: _filter,
          totalCount: allTanks.length,
          attentionCount: attentionCount,
          offlineCount: offlineCount,
          onSelected: (filter) => setState(() => _filter = filter),
        ),
        if (tanks.isEmpty)
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
                    builder: (context) => TankDetailScreen(
                      tank: tank,
                      snapshot: widget.snapshot,
                      user: widget.user,
                    ),
                  ),
                );
              },
            ),
          ),
        const SizedBox(height: 76),
      ],
    );
  }

  String get _emptyTitle {
    if (_query.trim().isNotEmpty) return 'No tanks match this search';
    return switch (_filter) {
      TankFilter.all => 'No tanks available',
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
          padding: EdgeInsets.fromLTRB(20, safeTop + 18, 20, 20),
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

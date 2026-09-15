import 'package:aqualogic/app/theme/app_colors.dart';
import 'package:aqualogic/features/auth/models/auth_user.dart';
import 'package:aqualogic/features/sensors/models/sensor_snapshot.dart';
import 'package:aqualogic/features/tanks/data/mock_tank_repository.dart';
import 'package:aqualogic/features/tanks/models/tank_info.dart';
import 'package:aqualogic/features/tanks/screens/tank_detail_screen.dart';
import 'package:aqualogic/features/tanks/widgets/tank_overview_card.dart';
import 'package:aqualogic/shared/models/aqualogic_status.dart';
import 'package:aqualogic/shared/widgets/app_page.dart';
import 'package:aqualogic/shared/widgets/header_panel.dart';
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
    final tanks = _visibleTanks(_repository.list(snapshot: widget.snapshot));
    return AppPage(
      header: HeaderPanel(
        compact: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            const Text(
              'Tanks',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 3),
            const Text(
              'A quick view of every monitored tank',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 14),
            TextField(
              onChanged: (value) => setState(() => _query = value),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search tanks...',
                prefixIcon: const Icon(LucideIcons.search),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 11),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
      ),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Your tanks',
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Text(
              '${tanks.length} shown',
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        _TankFilters(
          selected: _filter,
          onSelected: (filter) => setState(() => _filter = filter),
        ),
        if (tanks.isEmpty)
          const EmptyState(
            title: 'No tanks match this view',
            message: 'Try another filter or search term.',
            icon: LucideIcons.searchX,
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
      ],
    );
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
            TankFilter.needsAttention =>
              !tank.isRetired &&
                  (tank.operationalStatus == OperationalStatus.warning ||
                      tank.operationalStatus == OperationalStatus.critical),
            TankFilter.offline =>
              !tank.isRetired &&
                  tank.operationalStatus == OperationalStatus.offline,
          };
          return matchesQuery && matchesFilter;
        })
        .toList(growable: false);
  }
}

class _TankFilters extends StatelessWidget {
  const _TankFilters({required this.selected, required this.onSelected});

  final TankFilter selected;
  final ValueChanged<TankFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _FilterChip(
            label: 'All',
            icon: LucideIcons.layoutGrid,
            selected: selected == TankFilter.all,
            onTap: () => onSelected(TankFilter.all),
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: 'Needs attention',
            icon: LucideIcons.triangleAlert,
            selected: selected == TankFilter.needsAttention,
            onTap: () => onSelected(TankFilter.needsAttention),
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: 'Offline',
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
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      selected: selected,
      label: Text(label),
      avatar: Icon(icon, size: 15),
      onSelected: (_) => onTap(),
      showCheckmark: false,
      labelStyle: TextStyle(
        color: selected ? AppColors.tealDark : AppColors.text,
        fontSize: 11,
        fontWeight: FontWeight.w800,
      ),
      selectedColor: AppColors.mint,
      backgroundColor: Colors.white,
      side: const BorderSide(color: AppColors.line),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
    );
  }
}

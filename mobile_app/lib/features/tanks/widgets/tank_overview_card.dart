import 'package:aqualogic/app/theme/app_colors.dart';
import 'package:aqualogic/features/tanks/models/tank_info.dart';
import 'package:aqualogic/features/tanks/widgets/tank_visuals.dart';
import 'package:aqualogic/shared/models/aqualogic_status.dart';
import 'package:aqualogic/shared/widgets/semantic_status_widgets.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class TankOverviewCard extends StatelessWidget {
  const TankOverviewCard({super.key, required this.tank, required this.onTap});

  final TankInfo tank;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final speciesCount = tank.assignedSpeciesCount ?? tank.species.length;
    final isOffline =
        !tank.isRetired && tank.operationalStatus == OperationalStatus.offline;
    final condition = tank.isRetired
        ? 'Retired tank; monitoring is not expected.'
        : isOffline
        ? 'No current reading is available.'
        : tank.latestCondition ?? tank.description;
    final conditionLabel = _compactTankCondition(condition);

    return Semantics(
      button: true,
      label: 'Open ${tank.name} tank details',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey('tank-card-${tank.tankId}'),
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Ink(
            padding: const EdgeInsets.fromLTRB(14, 14, 12, 13),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.92),
              border: Border.all(color: AppColors.line),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TankIdentityMarker(initial: tank.initial, size: 48),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tank.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.text,
                              fontSize: 16,
                              height: 1.15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            tank.subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 11.5,
                              height: 1.25,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    tank.isRetired
                        ? const LifecycleBadge(compact: true)
                        : OperationalStatusBadge(
                            status: tank.operationalStatus,
                            compact: true,
                          ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        conditionLabel,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isOffline ? AppColors.offline : AppColors.text,
                          fontSize: 12.5,
                          height: 1.3,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Icon(
                      LucideIcons.chevronRight,
                      color: AppColors.muted,
                      size: 19,
                    ),
                  ],
                ),
                const SizedBox(height: 11),
                Wrap(
                  spacing: 12,
                  runSpacing: 5,
                  children: [
                    FreshnessLabel(
                      label: compactFreshnessLabel(tank.lastReportLabel),
                      isUnavailable: isOffline,
                    ),
                    if (speciesCount > 0)
                      _MetaLabel(
                        icon: LucideIcons.fish,
                        label: '$speciesCount species',
                      ),
                    _MetaLabel(
                      icon: LucideIcons.mapPin,
                      label: tank.locationOrType,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _compactTankCondition(String condition) {
  return switch (condition.trim()) {
    'All installed readings are within configured ranges.' =>
      'All readings within range',
    'TDS is outside the configured range.' => 'TDS outside configured range',
    _ => condition,
  };
}

class _MetaLabel extends StatelessWidget {
  const _MetaLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: AppColors.muted, size: 13),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.muted,
            fontSize: 10.5,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

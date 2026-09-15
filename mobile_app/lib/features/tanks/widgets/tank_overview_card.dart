import 'package:aqualogic/app/theme/app_colors.dart';
import 'package:aqualogic/features/tanks/models/tank_info.dart';
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
    final isOffline =
        !tank.isRetired && tank.operationalStatus == OperationalStatus.offline;
    return Semantics(
      button: true,
      label: 'Open ${tank.name} tank details',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Ink(
            padding: const EdgeInsets.fromLTRB(15, 15, 12, 13),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: AppColors.line),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: AppColors.tealDark.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 21,
                      backgroundColor: AppColors.teal.withValues(alpha: 0.25),
                      child: Text(
                        tank.initial,
                        style: const TextStyle(
                          color: AppColors.tealDark,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tank.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.text,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            tank.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
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
                const SizedBox(height: 13),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        tank.isRetired
                            ? 'Retired tank; monitoring is not expected.'
                            : isOffline
                            ? 'No current reading is available.'
                            : tank.latestCondition ?? tank.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isOffline ? AppColors.offline : AppColors.text,
                          fontSize: 12,
                          height: 1.3,
                          fontWeight: isOffline
                              ? FontWeight.w700
                              : FontWeight.w600,
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
                const SizedBox(height: 10),
                Wrap(
                  spacing: 14,
                  runSpacing: 5,
                  children: [
                    FreshnessLabel(
                      label: tank.lastReportLabel,
                      isUnavailable: isOffline,
                    ),
                    if (tank.species.isNotEmpty)
                      _MetaLabel(
                        icon: LucideIcons.fish,
                        label: '${tank.species.length} species',
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
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

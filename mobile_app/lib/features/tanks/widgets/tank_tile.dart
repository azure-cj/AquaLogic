import 'package:aqualogic/app/theme/app_colors.dart';
import 'package:aqualogic/features/tanks/models/tank_info.dart';
import 'package:aqualogic/shared/formatters/freshness_labels.dart';
import 'package:aqualogic/shared/models/aqualogic_status.dart';
import 'package:aqualogic/shared/widgets/semantic_status_widgets.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class TankTile extends StatelessWidget {
  const TankTile({super.key, required this.tank, this.onTap});

  final TankInfo tank;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              CircleAvatar(
                radius: 19,
                backgroundColor: AppColors.teal.withValues(alpha: 0.2),
                child: Text(
                  tank.initial,
                  style: const TextStyle(
                    color: AppColors.tealDark,
                    fontWeight: FontWeight.w700,
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
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    FreshnessLabel(
                      label: formatFreshnessLabel(tank.lastReportLabel),
                      isUnavailable:
                          !tank.isRetired &&
                          tank.operationalStatus == OperationalStatus.offline,
                    ),
                  ],
                ),
              ),
              tank.isRetired
                  ? const LifecycleBadge(compact: true)
                  : OperationalStatusBadge(
                      status: tank.operationalStatus,
                      compact: true,
                    ),
              const SizedBox(width: 4),
              const Icon(
                LucideIcons.chevronRight,
                color: AppColors.muted,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

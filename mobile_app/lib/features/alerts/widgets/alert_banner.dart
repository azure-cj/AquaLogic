import 'package:aqualogic/app/theme/app_colors.dart';
import 'package:aqualogic/features/alerts/data/build_alerts.dart';
import 'package:aqualogic/features/sensors/models/sensor_snapshot.dart';
import 'package:aqualogic/shared/widgets/semantic_status_widgets.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class AlertBanner extends StatelessWidget {
  const AlertBanner({super.key, required this.snapshot});

  final SensorSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final alerts = buildAlerts(snapshot);
    if (alerts.isEmpty) {
      return const EmptyState(
        title: 'No active water-quality alerts',
        message: 'Current parameter conditions do not need acknowledgement.',
      );
    }
    final alert = alerts.first;
    final color = alert.severity.name == 'critical'
        ? AppColors.critical
        : AppColors.warning;
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.65)),
        borderRadius: BorderRadius.circular(17),
      ),
      child: Row(
        children: [
          Icon(alert.icon, color: color, size: 24),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${alert.severity.name.toUpperCase()} · ${alert.parameter}',
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  alert.message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const Icon(LucideIcons.chevronRight, color: AppColors.muted),
        ],
      ),
    );
  }
}

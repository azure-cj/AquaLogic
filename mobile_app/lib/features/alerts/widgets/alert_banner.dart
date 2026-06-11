import 'package:aqualogic/app/theme/app_colors.dart';
import 'package:aqualogic/features/alerts/data/build_alerts.dart';
import 'package:aqualogic/features/sensors/models/sensor_snapshot.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class AlertBanner extends StatelessWidget {
  const AlertBanner({super.key, required this.snapshot});

  final SensorSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final alert = buildAlerts(snapshot).first;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: stateColor(alert.state).withValues(alpha: 0.10),
        border: Border.all(color: stateColor(alert.state)),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(alert.icon, color: stateColor(alert.state), size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  alert.title.toUpperCase(),
                  style: TextStyle(
                    color: stateColor(alert.state),
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  alert.message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.text, fontSize: 13),
                ),
              ],
            ),
          ),
          const Icon(LucideIcons.chevronRight, color: AppColors.critical),
        ],
      ),
    );
  }
}

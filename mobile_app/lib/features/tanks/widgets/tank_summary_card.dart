import 'package:aqualogic/app/theme/app_colors.dart';
import 'package:aqualogic/features/sensors/models/sensor_snapshot.dart';
import 'package:aqualogic/features/tanks/models/tank_info.dart';
import 'package:aqualogic/shared/models/aqualogic_status.dart';
import 'package:aqualogic/shared/formatters/freshness_labels.dart';
import 'package:aqualogic/shared/widgets/semantic_status_widgets.dart';
import 'package:aqualogic/shared/widgets/soft_card.dart';
import 'package:flutter/material.dart';

class TankSummaryCard extends StatelessWidget {
  const TankSummaryCard({
    super.key,
    required this.tank,
    required this.snapshot,
  });

  final TankInfo tank;
  final SensorSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final offline =
        !tank.isRetired && tank.operationalStatus == OperationalStatus.offline;
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tank.locationOrType.toUpperCase(),
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      tank.name,
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              tank.isRetired
                  ? const LifecycleBadge()
                  : OperationalStatusBadge(status: tank.operationalStatus),
            ],
          ),
          const SizedBox(height: 13),
          FreshnessLabel(
            label: formatFreshnessLabel(tank.lastReportLabel),
            isUnavailable: offline,
          ),
          const SizedBox(height: 10),
          Text(
            tank.latestCondition ?? tank.description,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

// Kept as a small reusable value row for clients that still use this widget.
class MiniMetric extends StatelessWidget {
  const MiniMetric({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

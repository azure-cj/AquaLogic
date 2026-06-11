import 'package:aqualogic/app/theme/app_colors.dart';
import 'package:aqualogic/features/sensors/models/sensor_snapshot.dart';
import 'package:aqualogic/features/tanks/models/tank_info.dart';
import 'package:aqualogic/features/tanks/models/tank_status.dart';
import 'package:aqualogic/shared/widgets/soft_card.dart';
import 'package:aqualogic/shared/widgets/status_pill.dart';
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
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tank.typeLabel.toUpperCase(),
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      tank.name,
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              StatusPill(
                label: tank.status,
                state: tankStatusState(tank.status),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: MiniMetric(label: 'HEALTH', value: '${tank.health}%'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: MiniMetric(label: 'VOLUME', value: tank.volumeLabel),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: MiniMetric(label: 'FED', value: tank.lastFedLabel),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            tank.description,
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class MiniMetric extends StatelessWidget {
  const MiniMetric({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

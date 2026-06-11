import 'package:aqualogic/app/theme/app_colors.dart';
import 'package:aqualogic/features/tanks/models/tank_info.dart';
import 'package:aqualogic/features/tanks/models/tank_status.dart';
import 'package:aqualogic/shared/widgets/soft_card.dart';
import 'package:aqualogic/shared/widgets/status_pill.dart';
import 'package:flutter/material.dart';

class TankTile extends StatelessWidget {
  const TankTile({super.key, required this.tank});

  final TankInfo tank;

  @override
  Widget build(BuildContext context) {
    final state = tankStatusState(tank.status);

    return SoftCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.teal,
            child: Text(
              tank.initial,
              style: const TextStyle(
                color: AppColors.text,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        tank.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.text,
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    StatusPill(label: tank.status, state: state),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  tank.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.muted, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${tank.health}%',
            style: const TextStyle(
              color: AppColors.text,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

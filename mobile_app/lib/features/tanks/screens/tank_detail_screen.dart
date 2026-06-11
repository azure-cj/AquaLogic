import 'package:aqualogic/app/theme/app_colors.dart';
import 'package:aqualogic/features/sensors/models/sensor_snapshot.dart';
import 'package:aqualogic/features/sensors/widgets/reading_grid.dart';
import 'package:aqualogic/features/tanks/models/tank_info.dart';
import 'package:aqualogic/features/tanks/models/tank_status.dart';
import 'package:aqualogic/features/tanks/widgets/tank_summary_card.dart';
import 'package:aqualogic/shared/widgets/app_page.dart';
import 'package:aqualogic/shared/widgets/header_panel.dart';
import 'package:aqualogic/shared/widgets/section_title.dart';
import 'package:aqualogic/shared/widgets/soft_card.dart';
import 'package:aqualogic/shared/widgets/status_pill.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class TankDetailScreen extends StatelessWidget {
  const TankDetailScreen({
    super.key,
    required this.tank,
    required this.snapshot,
  });

  final TankInfo tank;
  final SensorSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        top: false,
        child: AppPage(
          header: HeaderPanel(
            compact: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconButton.filledTonal(
                  tooltip: 'Back',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(LucideIcons.arrowLeft),
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tank.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            tank.subtitle,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    StatusPill(
                      label: tank.status,
                      state: tankStatusState(tank.status),
                      dark: true,
                    ),
                  ],
                ),
              ],
            ),
          ),
          children: [
            TankSummaryCard(tank: tank, snapshot: snapshot),
            const SectionTitle(title: 'Tank info'),
            Row(
              children: [
                Expanded(
                  child: _TankInfoCard(
                    icon: LucideIcons.waves,
                    label: 'Volume',
                    value: tank.volumeLabel,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _TankInfoCard(
                    icon: LucideIcons.utensils,
                    label: 'Last fed',
                    value: tank.lastFedLabel,
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: _TankInfoCard(
                    icon: LucideIcons.fish,
                    label: 'Type',
                    value: tank.typeLabel,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _TankInfoCard(
                    icon: LucideIcons.activity,
                    label: 'Health',
                    value: '${tank.health}%',
                  ),
                ),
              ],
            ),
            const SectionTitle(title: 'Live sensor readings'),
            ReadingGrid(snapshot: snapshot),
          ],
        ),
      ),
    );
  }
}

class _TankInfoCard extends StatelessWidget {
  const _TankInfoCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.tealDark, size: 20),
          const SizedBox(height: 10),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
            style: const TextStyle(color: AppColors.muted, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

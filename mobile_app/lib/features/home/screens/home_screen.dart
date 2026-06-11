import 'package:aqualogic/app/theme/app_colors.dart';
import 'package:aqualogic/features/alerts/widgets/header_alert_card.dart';
import 'package:aqualogic/features/demo/demo_data.dart';
import 'package:aqualogic/features/sensors/models/sensor_snapshot.dart';
import 'package:aqualogic/features/sensors/widgets/reading_grid.dart';
import 'package:aqualogic/features/tanks/widgets/tank_tile.dart';
import 'package:aqualogic/shared/widgets/app_page.dart';
import 'package:aqualogic/shared/widgets/connection_bell.dart';
import 'package:aqualogic/shared/widgets/header_panel.dart';
import 'package:aqualogic/shared/widgets/section_title.dart';
import 'package:aqualogic/shared/widgets/status_pill.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.snapshot,
    required this.onOpenAlerts,
  });

  final SensorSnapshot snapshot;
  final VoidCallback onOpenAlerts;

  @override
  Widget build(BuildContext context) {
    return AppPage(
      header: HeaderPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(
                  radius: 18,
                  backgroundColor: AppColors.teal,
                  child: Icon(
                    LucideIcons.droplets,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Good morning',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      Text(
                        'JRed Aquatics',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                        ),
                      ),
                    ],
                  ),
                ),
                ConnectionBell(isOnline: snapshot.isOnline),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  flex: 4,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'SYSTEM HEALTH',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '${snapshot.healthPercent}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 46,
                          fontWeight: FontWeight.w900,
                          height: 1,
                        ),
                      ),
                      const SizedBox(height: 10),
                      StatusPill(
                        label: snapshot.isOnline
                            ? snapshot.overallStatus
                            : 'OFFLINE',
                        state: snapshot.overallState,
                        dark: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 6,
                  child: HeaderAlertCard(
                    snapshot: snapshot,
                    onTap: onOpenAlerts,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      children: [
        SectionTitle(title: 'Live readings', action: 'Details', onTap: () {}),
        ReadingGrid(snapshot: snapshot),
        const SectionTitle(title: 'Tanks'),
        ...DemoData.tanks.map((tank) => TankTile(tank: tank)),
      ],
    );
  }
}

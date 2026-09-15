import 'package:aqualogic/app/theme/app_colors.dart';
import 'package:aqualogic/features/sensors/models/sensor_snapshot.dart';
import 'package:aqualogic/shared/widgets/app_page.dart';
import 'package:aqualogic/shared/widgets/header_panel.dart';
import 'package:aqualogic/shared/widgets/semantic_status_widgets.dart';
import 'package:aqualogic/shared/widgets/soft_card.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class DataStatusScreen extends StatelessWidget {
  const DataStatusScreen({super.key, required this.snapshot});

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
                  tooltip: 'Back to More',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(LucideIcons.arrowLeft),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Data status',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                const Text(
                  'A truthful view of this app\'s data boundary',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          children: [
            SoftCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(LucideIcons.database, color: AppColors.tealDark),
                      SizedBox(width: 9),
                      Text(
                        'Local demo data',
                        style: TextStyle(
                          color: AppColors.text,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const InfoRow(
                    label: 'Last refreshed',
                    value: 'Just now',
                    icon: LucideIcons.clock3,
                  ),
                  const Divider(height: 1),
                  InfoRow(
                    label: 'Sensor feed',
                    value: snapshot.isOnline
                        ? 'Local feed available'
                        : 'Feed unavailable',
                    icon: snapshot.isOnline
                        ? LucideIcons.radio
                        : LucideIcons.wifiOff,
                  ),
                ],
              ),
            ),
            const SectionHeader(
              title: 'Backend sync',
              subtitle: 'Future repository replacement point',
            ),
            const EmptyState(
              title: 'Not connected in this prototype',
              message:
                  'FastAPI, authentication, sensor sync, persistent alerts, and offline cache are intentionally deferred.',
              icon: LucideIcons.cloudOff,
            ),
          ],
        ),
      ),
    );
  }
}

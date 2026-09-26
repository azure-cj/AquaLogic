import 'package:aqualogic/app/theme/app_colors.dart';
import 'package:aqualogic/features/sensors/models/sensor_snapshot.dart';
import 'package:aqualogic/shared/widgets/app_page.dart';
import 'package:aqualogic/features/more/widgets/more_header.dart';
import 'package:aqualogic/shared/widgets/semantic_status_widgets.dart';
import 'package:aqualogic/shared/widgets/soft_card.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class DataStatusScreen extends StatelessWidget {
  const DataStatusScreen({
    super.key,
    required this.snapshot,
    this.isLiveData = false,
  });

  final SensorSnapshot snapshot;
  final bool isLiveData;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        top: false,
        child: AppPage(
          header: MoreHeader(
            title: 'Data status',
            subtitle: 'Configured data sources and current capabilities',
            onBack: () => Navigator.of(context).pop(),
          ),
          children: [
            SoftCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(LucideIcons.database, color: AppColors.tealDark),
                      SizedBox(width: 9),
                      Expanded(
                        child: FittedBox(
                          alignment: Alignment.centerLeft,
                          fit: BoxFit.scaleDown,
                          child: Text(
                            isLiveData
                                ? 'Railway API configured'
                                : 'Local demo data',
                            style: TextStyle(
                              color: AppColors.text,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  InfoRow(
                    label: 'Data source',
                    value: isLiveData
                        ? 'Production FastAPI'
                        : 'Local mock repositories',
                    icon: LucideIcons.database,
                  ),
                  const Divider(height: 1),
                  InfoRow(
                    label: isLiveData ? 'API reachability' : 'Sensor feed',
                    value: isLiveData
                        ? 'Shown with each request'
                        : snapshot.isOnline
                        ? 'Local feed available'
                        : 'Feed unavailable',
                    icon: isLiveData
                        ? LucideIcons.radio
                        : snapshot.isOnline
                        ? LucideIcons.radio
                        : LucideIcons.wifiOff,
                  ),
                ],
              ),
            ),
            SectionHeader(
              title: isLiveData ? 'Backend integration' : 'Backend sync',
              subtitle: isLiveData
                  ? 'Mobile features using Railway'
                  : 'Future repository replacement point',
            ),
            EmptyState(
              title: isLiveData
                  ? 'Railway data is in use'
                  : 'Not connected in this prototype',
              message: isLiveData
                  ? 'Authentication, Home, Tanks, Alerts and Monitoring, species, and Account identity use Railway. Alert handling is supported. Equipment state and history are admin-only and read-only. Offline cache, profile editing, push notifications, and physical controls are not enabled.'
                  : 'FastAPI, authentication, sensor sync, persistent alerts, and offline cache are intentionally deferred.',
              icon: isLiveData ? LucideIcons.cloud : LucideIcons.cloudOff,
            ),
          ],
        ),
      ),
    );
  }
}

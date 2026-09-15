import 'package:aqualogic/features/home/models/home_dashboard_data.dart';
import 'package:aqualogic/features/home/widgets/home_shared_widgets.dart';
import 'package:aqualogic/shared/widgets/section_title.dart';
import 'package:flutter/material.dart';

class StaffHomeContent extends StatelessWidget {
  const StaffHomeContent({
    super.key,
    required this.data,
    required this.onOpenAlerts,
    required this.onOpenTanks,
  });

  final HomeDashboardData data;
  final VoidCallback onOpenAlerts;
  final VoidCallback onOpenTanks;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle(title: 'Needs attention'),
        const SizedBox(height: 8),
        if (data.attentionItems.isEmpty)
          const EmptyAttentionCard(
            title: 'Nothing needs immediate attention',
            message: 'All monitored tanks are currently normal.',
          )
        else
          for (final item in data.attentionItems.take(3)) ...[
            AttentionCard(
              item: item,
              onAction: item.type == HomeAttentionType.monitoring
                  ? onOpenTanks
                  : onOpenAlerts,
            ),
            if (item != data.attentionItems.take(3).last)
              const SizedBox(height: 10),
          ],
        const SizedBox(height: 18),
        MonitoringSummaryCard(summary: data.monitoring),
        const SizedBox(height: 18),
        SectionTitle(
          title: 'Tank rounds',
          action: 'View all',
          onTap: onOpenTanks,
        ),
        const SizedBox(height: 8),
        TankFleetCard(
          tanks: data.tanks,
          showContext: true,
          onTap: (_) => onOpenTanks(),
        ),
        const SizedBox(height: 18),
        RecentActivitySection(activities: data.recentActivity),
      ],
    );
  }
}

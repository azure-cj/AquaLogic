import 'package:aqualogic/features/home/models/home_dashboard_data.dart';
import 'package:aqualogic/features/home/widgets/home_shared_widgets.dart';
import 'package:aqualogic/shared/widgets/section_title.dart';
import 'package:flutter/material.dart';

class OwnerHomeContent extends StatelessWidget {
  const OwnerHomeContent({
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
    final priorityItem = data.attentionItems.isEmpty
        ? null
        : data.attentionItems.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle(title: 'Highest priority'),
        const SizedBox(height: 8),
        if (priorityItem == null)
          const EmptyAttentionCard(
            title: 'All tanks operating normally',
            message: 'No current water-quality warnings.',
          )
        else
          AttentionCard(
            item: priorityItem,
            compact: true,
            onAction: priorityItem.type == HomeAttentionType.monitoring
                ? onOpenTanks
                : onOpenAlerts,
          ),
        const SizedBox(height: 18),
        SectionTitle(
          title: 'Fleet overview',
          action: 'View all',
          onTap: onOpenTanks,
        ),
        const SizedBox(height: 8),
        TankFleetCard(tanks: data.tanks, onTap: (_) => onOpenTanks()),
        const SizedBox(height: 18),
        MonitoringSummaryCard(summary: data.monitoring),
        const SizedBox(height: 18),
        RecentActivitySection(activities: data.recentActivity),
      ],
    );
  }
}

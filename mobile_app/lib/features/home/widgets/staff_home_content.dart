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
    this.isLiveData = false,
    this.onOpenTank,
    this.onOpenAlert,
  });

  final HomeDashboardData data;
  final VoidCallback onOpenAlerts;
  final VoidCallback onOpenTanks;
  final bool isLiveData;
  final ValueChanged<HomeTankSummary>? onOpenTank;
  final ValueChanged<HomeAttentionItem>? onOpenAlert;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PriorityAttentionSection(
          attentionItems: data.attentionItems,
          onOpenAlerts: onOpenAlerts,
          onOpenTanks: onOpenTanks,
          isLiveData: isLiveData,
          onOpenAlert: onOpenAlert,
        ),
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
          onTap: onOpenTank ?? (_) => onOpenTanks(),
        ),
        const SizedBox(height: 18),
        RecentActivitySection(activities: data.recentActivity),
      ],
    );
  }
}

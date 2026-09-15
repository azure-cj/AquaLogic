import 'package:aqualogic/app/theme/app_colors.dart';
import 'package:aqualogic/features/auth/models/auth_user.dart';
import 'package:aqualogic/features/auth/models/user_role.dart';
import 'package:aqualogic/features/home/models/home_dashboard_data.dart';
import 'package:aqualogic/shared/widgets/connection_bell.dart';
import 'package:aqualogic/shared/widgets/header_panel.dart';
import 'package:aqualogic/shared/widgets/semantic_status_widgets.dart';
import 'package:aqualogic/shared/widgets/section_title.dart';
import 'package:aqualogic/shared/widgets/soft_card.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class RoleHomeHeader extends StatelessWidget {
  const RoleHomeHeader({super.key, required this.user, required this.isOnline});

  final AuthUser user;
  final bool isOnline;

  @override
  Widget build(BuildContext context) {
    final organization = user.role == UserRole.admin
        ? 'JRed Aquatics'
        : 'Operations';

    return HeaderPanel(
      child: Row(
        children: [
          const CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.teal,
            child: Icon(LucideIcons.droplets, color: Colors.white, size: 19),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Good morning',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                Text(
                  user.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    _RoleBadge(label: user.role.badgeLabel),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        organization,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          ConnectionBell(isOnline: isOnline),
        ],
      ),
    );
  }
}

class FleetStatusSummary extends StatelessWidget {
  const FleetStatusSummary({super.key, required this.data});

  final HomeDashboardData data;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Aquarium status',
            style: TextStyle(
              color: AppColors.text,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${data.tanks.length} tanks in the local fleet',
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _SummaryMetric(
                  icon: LucideIcons.circleCheck,
                  color: AppColors.success,
                  value: data.normalTankCount,
                  label: 'Normal',
                ),
              ),
              Expanded(
                child: _SummaryMetric(
                  icon: LucideIcons.triangleAlert,
                  color: AppColors.warning,
                  value: data.needsAttentionCount,
                  label: 'Needs attention',
                ),
              ),
              Expanded(
                child: _SummaryMetric(
                  icon: LucideIcons.wifiOff,
                  color: AppColors.offline,
                  value: data.offlineTankCount,
                  label: 'Offline',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class AttentionCard extends StatelessWidget {
  const AttentionCard({super.key, required this.item, required this.onAction});

  final HomeAttentionItem item;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(item.status);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        border: Border.all(color: color.withValues(alpha: 0.7)),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: color.withValues(alpha: 0.14),
                child: Icon(_statusIcon(item.status), color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.tankName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 7),
                    OperationalStatusBadge(
                      status: item.status.asOperationalStatus,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            item.title,
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            item.message,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 12,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onAction,
              icon: const Icon(LucideIcons.arrowUpRight, size: 16),
              label: Text(item.actionLabel),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.tealDark,
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class EmptyAttentionCard extends StatelessWidget {
  const EmptyAttentionCard({
    super.key,
    required this.title,
    required this.message,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      child: Row(
        children: [
          const CircleAvatar(
            radius: 21,
            backgroundColor: AppColors.mint,
            child: Icon(LucideIcons.circleCheck, color: AppColors.tealDark),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class TankFleetCard extends StatelessWidget {
  const TankFleetCard({
    super.key,
    required this.tanks,
    required this.onTap,
    this.showContext = false,
  });

  final List<HomeTankSummary> tanks;
  final ValueChanged<HomeTankSummary> onTap;
  final bool showContext;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          for (var index = 0; index < tanks.length; index++) ...[
            TankStatusRow(
              tank: tanks[index],
              showContext: showContext,
              onTap: () => onTap(tanks[index]),
            ),
            if (index < tanks.length - 1)
              const Divider(height: 1, indent: 16, endIndent: 16),
          ],
        ],
      ),
    );
  }
}

class TankStatusRow extends StatelessWidget {
  const TankStatusRow({
    super.key,
    required this.tank,
    required this.onTap,
    this.showContext = false,
  });

  final HomeTankSummary tank;
  final VoidCallback onTap;
  final bool showContext;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              CircleAvatar(
                radius: 19,
                backgroundColor: AppColors.teal.withValues(alpha: 0.2),
                child: Text(
                  tank.initial,
                  style: const TextStyle(
                    color: AppColors.tealDark,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tank.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      showContext ? tank.contextLabel : tank.lastReportLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              OperationalStatusBadge(status: tank.status.asOperationalStatus),
              const SizedBox(width: 3),
              const Icon(
                LucideIcons.chevronRight,
                color: AppColors.muted,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MonitoringSummaryCard extends StatelessWidget {
  const MonitoringSummaryCard({super.key, required this.summary});

  final HomeMonitoringSummary summary;

  @override
  Widget build(BuildContext context) {
    final status = summary.sensorFeedOnline
        ? HomeOperationalStatus.normal
        : HomeOperationalStatus.offline;
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                LucideIcons.radio,
                color: AppColors.tealDark,
                size: 20,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Monitoring',
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              OperationalStatusBadge(
                status: status.asOperationalStatus,
                label: summary.sensorFeedOnline
                    ? 'Feed online'
                    : 'Feed unavailable',
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _MonitoringMetric(
                  value:
                      '${summary.reportingTankCount} of ${summary.totalTankCount}',
                  label: 'tanks reporting',
                  icon: LucideIcons.activity,
                ),
              ),
              Expanded(
                child: _MonitoringMetric(
                  value: '${summary.outageCount}',
                  label: 'monitoring outages',
                  icon: LucideIcons.wifiOff,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Reporting state is separate from water-quality alerts.',
            style: TextStyle(color: AppColors.muted, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class RecentActivitySection extends StatelessWidget {
  const RecentActivitySection({super.key, required this.activities});

  final List<HomeActivityItem> activities;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(title: 'Recent activity'),
        SoftCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              for (var index = 0; index < activities.length; index++) ...[
                _ActivityRow(activity: activities[index]),
                if (index < activities.length - 1)
                  const Divider(height: 1, indent: 16, endIndent: 16),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.activity});

  final HomeActivityItem activity;

  @override
  Widget build(BuildContext context) {
    final icon = switch (activity.type) {
      HomeActivityType.feeding => LucideIcons.utensils,
      HomeActivityType.uvCycle => LucideIcons.sun,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.teal.withValues(alpha: 0.16),
            child: Icon(icon, color: AppColors.tealDark, size: 17),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  activity.title,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${activity.tankName} · ${activity.timeLabel}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.muted, fontSize: 11),
                ),
              ],
            ),
          ),
          const Icon(
            LucideIcons.circleCheck,
            color: AppColors.success,
            size: 18,
          ),
        ],
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 19),
        const SizedBox(height: 6),
        Text(
          '$value',
          style: const TextStyle(
            color: AppColors.text,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.muted,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _MonitoringMetric extends StatelessWidget {
  const _MonitoringMetric({
    required this.value,
    required this.label,
    required this.icon,
  });

  final String value;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppColors.tealDark, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.text,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.muted, fontSize: 10),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.mint.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.tealDark,
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.7,
        ),
      ),
    );
  }
}

Color _statusColor(HomeOperationalStatus status) {
  return switch (status) {
    HomeOperationalStatus.normal => AppColors.success,
    HomeOperationalStatus.warning => AppColors.warning,
    HomeOperationalStatus.critical => AppColors.critical,
    HomeOperationalStatus.offline => AppColors.offline,
  };
}

IconData _statusIcon(HomeOperationalStatus status) {
  return switch (status) {
    HomeOperationalStatus.normal => LucideIcons.circleCheck,
    HomeOperationalStatus.warning => LucideIcons.triangleAlert,
    HomeOperationalStatus.critical => LucideIcons.circleAlert,
    HomeOperationalStatus.offline => LucideIcons.wifiOff,
  };
}

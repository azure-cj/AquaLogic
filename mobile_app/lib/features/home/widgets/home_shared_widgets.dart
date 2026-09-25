import 'package:aqualogic/app/theme/app_colors.dart';
import 'package:aqualogic/app/theme/app_tokens.dart';
import 'package:aqualogic/shared/formatters/freshness_labels.dart';
import 'package:aqualogic/features/auth/models/auth_user.dart';
import 'package:aqualogic/features/auth/models/user_role.dart';
import 'package:aqualogic/features/home/models/home_dashboard_data.dart';
import 'package:aqualogic/shared/widgets/connection_bell.dart';
import 'package:aqualogic/shared/widgets/semantic_status_widgets.dart';
import 'package:aqualogic/shared/widgets/section_title.dart';
import 'package:aqualogic/shared/widgets/soft_card.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class HomeHero extends StatelessWidget {
  const HomeHero({
    super.key,
    required this.user,
    required this.isOnline,
    required this.data,
    required this.showFleetStatus,
    this.isLoading = false,
  });

  final AuthUser user;
  final bool? isOnline;
  final HomeDashboardData? data;
  final bool showFleetStatus;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    final organization = user.role == UserRole.admin
        ? 'JRed Aquatics'
        : 'Operations';

    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(26),
          ),
          child: SizedBox(
            height: 210,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.background, AppColors.mint],
                    ),
                  ),
                ),
                Positioned(
                  left: -110,
                  right: -110,
                  bottom: -1,
                  height: 132,
                  child: IgnorePointer(
                    child: ExcludeSemantics(
                      child: Opacity(
                        opacity: 0.82,
                        child: Image.asset(
                          key: const ValueKey('home-hero-illustration'),
                          'assets/images/owner_home_hero.png',
                          fit: BoxFit.cover,
                          alignment: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  top: topInset + 14,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Semantics(
                            image: true,
                            label: 'AquaLogic logo',
                            child: Image.asset(
                              'assets/images/aqualogic_icon.png',
                              width: 24,
                              height: 24,
                              fit: BoxFit.contain,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: FittedBox(
                              alignment: Alignment.centerLeft,
                              fit: BoxFit.scaleDown,
                              child: Text(
                                'AquaLogic',
                                style: TextStyle(
                                  color: AppColors.text,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                          const Spacer(),
                          ConnectionBell(isOnline: isOnline, light: true),
                        ],
                      ),
                      const SizedBox(height: 17),
                      const Text(
                        'Good morning,',
                        style: TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        user.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.text,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          height: 1.05,
                        ),
                      ),
                      const SizedBox(height: 7),
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
                                color: AppColors.muted,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (showFleetStatus && (data != null || isLoading))
          Padding(
            padding: const EdgeInsets.only(top: 186),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.pageGutter,
              ),
              child: data == null
                  ? const _FleetStatusLoadingSheet()
                  : FleetStatusSheet(data: data!),
            ),
          ),
      ],
    );
  }
}

class _FleetStatusLoadingSheet extends StatelessWidget {
  const _FleetStatusLoadingSheet();

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Container(
      key: const ValueKey('fleet-status-loading'),
      height: 113,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.line),
        boxShadow: [
          BoxShadow(
            color: AppColors.tealDark.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Loading fleet status',
            style: TextStyle(
              color: AppColors.muted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            minHeight: 3,
            backgroundColor: AppColors.background,
            color: AppColors.teal,
            value: reduceMotion ? 0.65 : null,
          ),
        ],
      ),
    );
  }
}

class FleetStatusSheet extends StatelessWidget {
  const FleetStatusSheet({super.key, required this.data});

  final HomeDashboardData data;

  @override
  Widget build(BuildContext context) {
    final headline = _fleetStatusHeadline(data);
    final hasAttention = data.needsAttentionCount > 0;
    final headlineColor = hasAttention && data.attentionItems.isNotEmpty
        ? _statusColor(data.attentionItems.first.status)
        : AppColors.tealDark;
    final tankWord = data.tanks.length == 1 ? 'tank' : 'tanks';

    return Semantics(
      container: true,
      label:
          'Fleet status. $headline. ${data.tanks.length} $tankWord, '
          '${data.normalTankCount} normal, ${data.needsAttentionCount} need attention, '
          '${data.offlineTankCount} offline.',
      child: Container(
        key: const ValueKey('fleet-status-sheet'),
        padding: const EdgeInsets.fromLTRB(16, 15, 16, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.line),
          boxShadow: [
            BoxShadow(
              color: AppColors.tealDark.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (hasAttention) ...[
                  Icon(
                    _statusIcon(data.attentionItems.first.status),
                    color: headlineColor,
                    size: 18,
                  ),
                  const SizedBox(width: 7),
                ],
                Expanded(
                  child: Text(
                    headline,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.text,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${data.tanks.length} $tankWord · ${data.normalTankCount} normal · '
              '${data.needsAttentionCount} need attention · ${data.offlineTankCount} offline',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 14),
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
                const _MetricDivider(),
                Expanded(
                  child: _SummaryMetric(
                    icon: LucideIcons.triangleAlert,
                    color: AppColors.warning,
                    value: data.needsAttentionCount,
                    label: 'Needs\nattention',
                  ),
                ),
                const _MetricDivider(),
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
      ),
    );
  }
}

class PriorityAttentionSection extends StatelessWidget {
  const PriorityAttentionSection({
    super.key,
    required this.attentionItems,
    required this.onOpenAlerts,
    required this.onOpenTanks,
    this.isLiveData = false,
    this.onOpenAlert,
  });

  final List<HomeAttentionItem> attentionItems;
  final VoidCallback onOpenAlerts;
  final VoidCallback onOpenTanks;
  final bool isLiveData;
  final ValueChanged<HomeAttentionItem>? onOpenAlert;

  @override
  Widget build(BuildContext context) {
    if (attentionItems.isEmpty) return const SizedBox.shrink();

    final priorityItem = attentionItems.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          title: attentionItems.length == 1
              ? 'Needs attention'
              : 'Highest priority',
          action: 'View all alerts',
          actionArrow: true,
          onTap: onOpenAlerts,
        ),
        const SizedBox(height: 8),
        AttentionCard(
          item: priorityItem,
          compact: true,
          onAction: onOpenAlert == null
              ? priorityItem.type == HomeAttentionType.monitoring
                    ? onOpenTanks
                    : onOpenAlerts
              : () => onOpenAlert!(priorityItem),
        ),
        const SizedBox(height: 18),
      ],
    );
  }
}

class AttentionCard extends StatelessWidget {
  const AttentionCard({
    super.key,
    required this.item,
    required this.onAction,
    this.compact = false,
  });

  final HomeAttentionItem item;
  final VoidCallback onAction;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return _CompactAttentionCard(item: item, onAction: onAction);
    }

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
                        fontWeight: FontWeight.w700,
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
              fontWeight: FontWeight.w700,
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

class _CompactAttentionCard extends StatelessWidget {
  const _CompactAttentionCard({required this.item, required this.onAction});

  final HomeAttentionItem item;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final category = item.type == HomeAttentionType.waterQuality
        ? 'Water quality'
        : 'Monitoring';
    final actionSemantics = item.type == HomeAttentionType.waterQuality
        ? 'View ${item.tankName} ${item.status.label.toLowerCase()} alert'
        : 'View ${item.tankName} monitoring incident';

    return Semantics(
      container: true,
      label:
          '${item.tankName}, ${item.status.label}, ${item.title}, '
          '${item.message}, ${item.actionLabel}',
      child: Container(
        key: const ValueKey('owner-priority-card'),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white,
              AppColors.background.withValues(alpha: 0.42),
            ],
          ),
          border: Border.all(color: AppColors.line),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: AppColors.tealDark.withValues(alpha: 0.035),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: IntrinsicHeight(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 10, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        item.tankName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OperationalStatusBadge(
                      key: const ValueKey('owner-priority-severity-pill'),
                      status: item.status.asOperationalStatus,
                      compact: true,
                      leadingText: item.status == HomeOperationalStatus.critical
                          ? '!'
                          : null,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  item.title,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 11.5,
                    height: 1.3,
                  ),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        category,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Semantics(
                      button: true,
                      label: actionSemantics,
                      child: TextButton.icon(
                        onPressed: onAction,
                        icon: const Icon(LucideIcons.arrowUpRight, size: 14),
                        label: Text(item.actionLabel),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.tealDark,
                          minimumSize: const Size(0, 48),
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          textStyle: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
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
                    fontWeight: FontWeight.w700,
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
    if (tanks.isEmpty) {
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
              child: Text(
                'No active tanks are assigned to this fleet.',
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ),
          ],
        ),
      );
    }
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
                    fontWeight: FontWeight.w700,
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
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      showContext
                          ? '${tank.contextLabel} · ${formatFreshnessLabel(tank.lastReportLabel)}'
                          : formatFreshnessLabel(tank.lastReportLabel),
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
    final status = !summary.incidentDetailsAvailable
        ? HomeOperationalStatus.warning
        : summary.outageCount == 0
        ? HomeOperationalStatus.normal
        : HomeOperationalStatus.offline;
    final badgeLabel = !summary.incidentDetailsAvailable
        ? 'Unavailable'
        : summary.outageCount == 0
        ? 'No incidents'
        : '${summary.outageCount} active';
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
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              OperationalStatusBadge(
                status: status.asOperationalStatus,
                label: badgeLabel,
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
                  label: 'active incidents',
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
    if (activities.isEmpty) return const SizedBox.shrink();
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
                    fontWeight: FontWeight.w700,
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

class _MetricDivider extends StatelessWidget {
  const _MetricDivider();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 12,
      child: Center(
        child: Container(
          width: 1,
          height: 42,
          color: AppColors.line.withValues(alpha: 0.72),
        ),
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
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, color: color, size: 19),
        const SizedBox(height: 6),
        Text(
          '$value',
          style: const TextStyle(
            color: AppColors.text,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(
          width: double.infinity,
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
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
                  fontWeight: FontWeight.w700,
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
          fontWeight: FontWeight.w700,
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

String _fleetStatusHeadline(HomeDashboardData data) {
  if (data.tanks.isEmpty) return 'No tanks in the fleet';
  if (data.needsAttentionCount > 0) {
    final tankWord = data.needsAttentionCount == 1 ? 'tank' : 'tanks';
    return '${data.needsAttentionCount} $tankWord need attention';
  }
  if (data.offlineTankCount == data.tanks.length) {
    return 'All tanks offline';
  }
  if (data.offlineTankCount > 0) {
    final tankWord = data.offlineTankCount == 1 ? 'tank is' : 'tanks are';
    return '${data.offlineTankCount} $tankWord offline';
  }
  return 'All tanks look good';
}

IconData _statusIcon(HomeOperationalStatus status) {
  return switch (status) {
    HomeOperationalStatus.normal => LucideIcons.circleCheck,
    HomeOperationalStatus.warning => LucideIcons.triangleAlert,
    HomeOperationalStatus.critical => LucideIcons.circleAlert,
    HomeOperationalStatus.offline => LucideIcons.wifiOff,
  };
}

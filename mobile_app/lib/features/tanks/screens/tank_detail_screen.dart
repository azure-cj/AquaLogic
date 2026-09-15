import 'package:aqualogic/app/theme/app_colors.dart';
import 'package:aqualogic/features/auth/models/auth_user.dart';
import 'package:aqualogic/features/auth/models/user_role.dart';
import 'package:aqualogic/features/control/screens/equipment_screen.dart';
import 'package:aqualogic/features/fish/screens/fish_library_screen.dart';
import 'package:aqualogic/features/sensors/models/sensor_snapshot.dart';
import 'package:aqualogic/features/sensors/widgets/reading_grid.dart';
import 'package:aqualogic/features/tanks/models/tank_info.dart';
import 'package:aqualogic/shared/models/aqualogic_status.dart';
import 'package:aqualogic/shared/widgets/app_page.dart';
import 'package:aqualogic/shared/widgets/header_panel.dart';
import 'package:aqualogic/shared/widgets/semantic_status_widgets.dart';
import 'package:aqualogic/shared/widgets/soft_card.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class TankDetailScreen extends StatelessWidget {
  const TankDetailScreen({
    super.key,
    required this.tank,
    required this.snapshot,
    this.user,
  });

  final TankInfo tank;
  final SensorSnapshot snapshot;
  final AuthUser? user;

  @override
  Widget build(BuildContext context) {
    final isRetired = tank.isRetired;
    final isOffline =
        !isRetired && tank.operationalStatus == OperationalStatus.offline;
    final canManageEquipment =
        !isRetired && (user == null || user!.role == UserRole.admin);

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
                  tooltip: 'Back to Tanks',
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
                          const SizedBox(height: 3),
                          Text(
                            tank.subtitle,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(
                                isOffline
                                    ? LucideIcons.wifiOff
                                    : LucideIcons.clock3,
                                color: Colors.white70,
                                size: 14,
                              ),
                              const SizedBox(width: 5),
                              Flexible(
                                child: Text(
                                  tank.lastReportLabel,
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
                    const SizedBox(width: 8),
                    isRetired
                        ? const LifecycleBadge(compact: true)
                        : OperationalStatusBadge(
                            status: tank.operationalStatus,
                            compact: true,
                          ),
                  ],
                ),
              ],
            ),
          ),
          children: [
            _TankIdentityCard(tank: tank),
            const SectionHeader(
              title: 'Current readings',
              subtitle: 'Installed sensors only',
            ),
            ReadingGrid(snapshot: snapshot, readings: tank.readings),
            const SectionHeader(
              title: 'Recent issues',
              subtitle: 'Water quality and monitoring are separate',
            ),
            _IssuesSection(issues: tank.issues),
            const SectionHeader(
              title: 'Species',
              subtitle: 'Advisory suitability for this tank',
            ),
            _SpeciesSnapshot(
              tank: tank,
              onSpeciesTap: (speciesId) {
                final assignment = tank.species.firstWhere(
                  (species) => species.speciesId == speciesId,
                );
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => SpeciesDetailScreen(
                      speciesId: speciesId,
                      assignedTankName: tank.name,
                      suitability: assignment.suitability,
                    ),
                  ),
                );
              },
            ),
            const SectionHeader(
              title: 'Monitoring',
              subtitle: 'Reporting state, not water quality',
            ),
            _MonitoringCard(tank: tank),
            if (canManageEquipment) ...[
              const SectionHeader(
                title: 'Equipment',
                subtitle: 'Tank-specific devices and controls',
              ),
              _EquipmentEntry(
                tank: tank,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) =>
                          EquipmentScreen(tank: tank, user: user),
                    ),
                  );
                },
              ),
            ],
            const SectionHeader(title: 'Recent activity'),
            _ActivitySection(activities: tank.recentActivity),
          ],
        ),
      ),
    );
  }
}

class _TankIdentityCard extends StatelessWidget {
  const _TankIdentityCard({required this.tank});

  final TankInfo tank;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tank information',
            style: TextStyle(
              color: AppColors.text,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            tank.description,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 12,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 8),
          InfoRow(
            label: 'Location',
            value: tank.locationOrType,
            icon: LucideIcons.mapPin,
          ),
          const Divider(height: 1),
          InfoRow(
            label: 'Volume',
            value: tank.volumeLabel,
            icon: LucideIcons.waves,
          ),
          const Divider(height: 1),
          InfoRow(
            label: 'Last fed',
            value: tank.lastFedLabel,
            icon: LucideIcons.utensils,
          ),
        ],
      ),
    );
  }
}

class _IssuesSection extends StatelessWidget {
  const _IssuesSection({required this.issues});

  final List<TankIssue> issues;

  @override
  Widget build(BuildContext context) {
    if (issues.isEmpty) {
      return const EmptyState(
        title: 'No recent tank issues',
        message:
            'No water-quality alerts or monitoring interruptions are listed.',
      );
    }
    return Column(
      children: [
        for (var index = 0; index < issues.length; index++) ...[
          _IssueCard(issue: issues[index]),
          if (index < issues.length - 1) const SizedBox(height: 9),
        ],
      ],
    );
  }
}

class _IssueCard extends StatelessWidget {
  const _IssueCard({required this.issue});

  final TankIssue issue;

  @override
  Widget build(BuildContext context) {
    final isMonitoring = issue.category == TankIssueCategory.monitoring;
    final color = isMonitoring
        ? AppColors.offline
        : switch (issue.severity) {
            TankIssueSeverity.critical => AppColors.critical,
            TankIssueSeverity.warning => AppColors.warning,
            TankIssueSeverity.info => AppColors.offline,
          };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isMonitoring ? LucideIcons.wifiOff : LucideIcons.circleAlert,
            color: color,
            size: 21,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isMonitoring ? 'Monitoring' : 'Water quality',
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  issue.title,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  issue.message,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 11,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${issue.lifecycle == TankIssueLifecycle.active ? 'Active' : issue.lifecycle.name} · ${issue.timeLabel}',
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SpeciesSnapshot extends StatelessWidget {
  const _SpeciesSnapshot({required this.tank, required this.onSpeciesTap});

  final TankInfo tank;
  final ValueChanged<String> onSpeciesTap;

  @override
  Widget build(BuildContext context) {
    if (tank.species.isEmpty) {
      return const EmptyState(
        title: 'No species assigned to this tank',
        message: 'Assigned livestock will appear here when available.',
        icon: LucideIcons.fish,
      );
    }
    return SoftCard(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        children: [
          for (var index = 0; index < tank.species.length; index++) ...[
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => onSpeciesTap(tank.species[index].speciesId),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 11,
                  ),
                  child: Row(
                    children: [
                      const CircleAvatar(
                        radius: 18,
                        backgroundColor: AppColors.mint,
                        child: Icon(
                          LucideIcons.fish,
                          color: AppColors.tealDark,
                          size: 17,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          tank.species[index].name,
                          style: const TextStyle(
                            color: AppColors.text,
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      SpeciesSuitabilityBadge(
                        suitability: tank.species[index].suitability,
                        compact: true,
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        LucideIcons.chevronRight,
                        color: AppColors.muted,
                        size: 17,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (index < tank.species.length - 1)
              const Divider(height: 1, indent: 12, endIndent: 12),
          ],
        ],
      ),
    );
  }
}

class _MonitoringCard extends StatelessWidget {
  const _MonitoringCard({required this.tank});

  final TankInfo tank;

  @override
  Widget build(BuildContext context) {
    if (tank.isRetired) {
      return const SoftCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(LucideIcons.archive, color: AppColors.muted, size: 22),
            SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Tank retired',
                          style: TextStyle(
                            color: AppColors.text,
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      LifecycleBadge(compact: true),
                    ],
                  ),
                  SizedBox(height: 5),
                  Text(
                    'Monitoring is not expected for retired tanks. Historical readings remain available for context.',
                    style: TextStyle(
                      color: AppColors.muted,
                      fontSize: 11,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final offline = tank.operationalStatus == OperationalStatus.offline;
    return SoftCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            offline ? LucideIcons.wifiOff : LucideIcons.radio,
            color: offline ? AppColors.offline : AppColors.tealDark,
            size: 22,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        offline ? 'Monitoring outage' : 'Reporting normally',
                        style: const TextStyle(
                          color: AppColors.text,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    OperationalStatusBadge(
                      status: offline
                          ? OperationalStatus.offline
                          : OperationalStatus.normal,
                      label: offline ? 'No recent data' : 'Reporting',
                      compact: true,
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  offline
                      ? 'A reporting interruption does not automatically mean the water is unsafe.'
                      : 'AquaLogic is receiving recent data for this tank.',
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EquipmentEntry extends StatelessWidget {
  const _EquipmentEntry({required this.tank, required this.onTap});

  final TankInfo tank;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Open equipment for ${tank.name}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(17),
          onTap: onTap,
          child: Ink(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.tealDark,
              borderRadius: BorderRadius.circular(17),
            ),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 21,
                  backgroundColor: Colors.white24,
                  child: Icon(
                    LucideIcons.slidersHorizontal,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Equipment',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        '${tank.equipmentCount} connected devices',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const Text(
                  'View equipment',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 3),
                const Icon(
                  LucideIcons.chevronRight,
                  color: Colors.white,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActivitySection extends StatelessWidget {
  const _ActivitySection({required this.activities});

  final List<TankActivity> activities;

  @override
  Widget build(BuildContext context) {
    if (activities.isEmpty) {
      return const EmptyState(
        title: 'No recent activity',
        message: 'Tank activity will appear here as the local demo changes.',
        icon: LucideIcons.history,
      );
    }
    return SoftCard(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        children: [
          for (var index = 0; index < activities.length; index++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 18,
                    backgroundColor: AppColors.mint,
                    child: Icon(
                      LucideIcons.activity,
                      color: AppColors.tealDark,
                      size: 17,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          activities[index].title,
                          style: const TextStyle(
                            color: AppColors.text,
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          activities[index].detail,
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    activities[index].timeLabel,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            if (index < activities.length - 1)
              const Divider(height: 1, indent: 12, endIndent: 12),
          ],
        ],
      ),
    );
  }
}

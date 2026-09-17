import 'package:aqualogic/app/theme/app_colors.dart';
import 'package:aqualogic/features/auth/models/auth_user.dart';
import 'package:aqualogic/features/auth/models/user_role.dart';
import 'package:aqualogic/features/control/screens/equipment_screen.dart';
import 'package:aqualogic/features/fish/screens/fish_library_screen.dart';
import 'package:aqualogic/features/sensors/models/sensor_snapshot.dart';
import 'package:aqualogic/features/sensors/widgets/reading_grid.dart';
import 'package:aqualogic/features/tanks/models/tank_info.dart';
import 'package:aqualogic/features/tanks/widgets/tank_visuals.dart';
import 'package:aqualogic/shared/models/aqualogic_status.dart';
import 'package:aqualogic/shared/formatters/freshness_labels.dart';
import 'package:aqualogic/shared/widgets/app_page.dart';
import 'package:aqualogic/shared/widgets/semantic_status_widgets.dart';
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
    final canManageEquipment =
        !isRetired && (user == null || user!.role == UserRole.admin);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        top: false,
        child: AppPage(
          header: _TankDetailHeader(tank: tank),
          children: [
            const SectionHeader(
              title: 'Current readings',
              subtitle: 'Live readings from installed sensors',
            ),
            ReadingGrid(snapshot: snapshot, readings: tank.readings),
            const SectionHeader(
              title: 'Issues',
              subtitle: 'Water quality and monitoring',
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
            _MonitoringRow(tank: tank),
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
            const SectionHeader(
              title: 'Recent activity',
              subtitle: 'Latest tank events',
            ),
            _ActivitySection(activities: tank.recentActivity),
          ],
        ),
      ),
    );
  }
}

class _TankDetailHeader extends StatelessWidget {
  const _TankDetailHeader({required this.tank});

  final TankInfo tank;

  @override
  Widget build(BuildContext context) {
    final safeTop = MediaQuery.paddingOf(context).top;
    final isOffline =
        !tank.isRetired && tank.operationalStatus == OperationalStatus.offline;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: ExcludeSemantics(
                  child: Opacity(
                    opacity: 0.30,
                    child: Image.asset(
                      'assets/images/tank_header.png',
                      fit: BoxFit.cover,
                      alignment: Alignment.centerRight,
                    ),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        AppColors.background.withValues(alpha: 0.92),
                        AppColors.background.withValues(alpha: 0.70),
                        AppColors.background.withValues(alpha: 0.38),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 156),
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.fromLTRB(16, safeTop + 10, 16, 17),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: AppColors.line.withValues(alpha: 0.72),
                    ),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Semantics(
                          button: true,
                          label: 'Back to Tanks',
                          child: IconButton(
                            tooltip: 'Back to Tanks',
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(LucideIcons.arrowLeft),
                            style: IconButton.styleFrom(
                              minimumSize: const Size(48, 48),
                              foregroundColor: AppColors.tealDark,
                              backgroundColor: Colors.white.withValues(
                                alpha: 0.76,
                              ),
                              side: const BorderSide(color: AppColors.line),
                            ),
                          ),
                        ),
                        const Spacer(),
                        tank.isRetired
                            ? const LifecycleBadge(compact: true)
                            : OperationalStatusBadge(
                                status: tank.operationalStatus,
                                compact: true,
                              ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TankIdentityMarker(initial: tank.initial, size: 52),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tank.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.text,
                                  fontSize: 25,
                                  height: 1.08,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                tank.subtitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 13,
                                  height: 1.2,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 7),
                              Row(
                                children: [
                                  Icon(
                                    isOffline
                                        ? LucideIcons.wifiOff
                                        : LucideIcons.clock3,
                                    color: isOffline
                                        ? AppColors.offline
                                        : AppColors.muted,
                                    size: 14,
                                  ),
                                  const SizedBox(width: 5),
                                  Flexible(
                                    child: Text(
                                      formatFreshnessLabel(
                                        tank.lastReportLabel,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: isOffline
                                            ? AppColors.offline
                                            : AppColors.muted,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
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
                  ],
                ),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: _TankMetadataStrip(tank: tank),
        ),
      ],
    );
  }
}

class _TankMetadataStrip extends StatelessWidget {
  const _TankMetadataStrip({required this.tank});

  final TankInfo tank;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.78),
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(17),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            Expanded(
              child: _MetadataItem(
                icon: LucideIcons.mapPin,
                label: 'Location',
                value: tank.locationOrType,
              ),
            ),
            const VerticalDivider(
              width: 1,
              thickness: 1,
              color: AppColors.line,
            ),
            Expanded(
              child: _MetadataItem(
                icon: LucideIcons.waves,
                label: 'Volume',
                value: tank.volumeLabel,
              ),
            ),
            const VerticalDivider(
              width: 1,
              thickness: 1,
              color: AppColors.line,
            ),
            Expanded(
              child: _MetadataItem(
                icon: LucideIcons.utensils,
                label: 'Last fed',
                value: tank.lastFedLabel,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetadataItem extends StatelessWidget {
  const _MetadataItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.tealDark, size: 15),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 13,
              height: 1.15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailSurface extends StatelessWidget {
  const _DetailSurface({
    required this.child,
    this.padding = const EdgeInsets.all(14),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(18),
      ),
      child: child,
    );
  }
}

class _IssuesSection extends StatelessWidget {
  const _IssuesSection({required this.issues});

  final List<TankIssue> issues;

  @override
  Widget build(BuildContext context) {
    if (issues.isEmpty) {
      return Semantics(
        container: true,
        label: 'No active water-quality or monitoring issues',
        child: _DetailSurface(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.mint,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  LucideIcons.check,
                  color: AppColors.tealDark,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'No active issues',
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 12,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        for (var index = 0; index < issues.length; index++) ...[
          _IssueRow(issue: issues[index]),
          if (index < issues.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _IssueRow extends StatelessWidget {
  const _IssueRow({required this.issue});

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
    final category = isMonitoring ? 'Monitoring' : 'Water quality';
    return Semantics(
      container: true,
      label: '$category, ${issue.title}, ${issue.message}',
      child: _DetailSurface(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isMonitoring ? LucideIcons.wifiOff : LucideIcons.circleAlert,
                color: color,
                size: 17,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    category,
                    style: TextStyle(
                      color: color,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    issue.title,
                    style: const TextStyle(
                      color: AppColors.text,
                      fontSize: 13,
                      height: 1.2,
                      fontWeight: FontWeight.w600,
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
                  const SizedBox(height: 5),
                  Text(
                    '${issue.lifecycle == TankIssueLifecycle.active ? 'Active' : issue.lifecycle.name} · ${issue.timeLabel}',
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
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
      return const _DetailSurface(
        child: Row(
          children: [
            Icon(LucideIcons.fish, color: AppColors.muted, size: 19),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'No species assigned to this tank',
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return _DetailSurface(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var index = 0; index < tank.species.length; index++) ...[
            _SpeciesRow(
              species: tank.species[index],
              onTap: () => onSpeciesTap(tank.species[index].speciesId),
            ),
            if (index < tank.species.length - 1)
              const Divider(height: 1, indent: 13, endIndent: 13),
          ],
        ],
      ),
    );
  }
}

class _SpeciesRow extends StatelessWidget {
  const _SpeciesRow({required this.species, required this.onTap});

  final TankSpeciesSummary species;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      onTap: onTap,
      label:
          '${species.name}, species suitability ${species.suitability.label}',
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: AppColors.mint,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      LucideIcons.fish,
                      color: AppColors.tealDark,
                      size: 17,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      species.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 13,
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  SpeciesSuitabilityBadge(
                    suitability: species.suitability,
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
      ),
    );
  }
}

class _MonitoringRow extends StatelessWidget {
  const _MonitoringRow({required this.tank});

  final TankInfo tank;

  @override
  Widget build(BuildContext context) {
    if (tank.isRetired) {
      return const _DetailSurface(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(LucideIcons.archive, color: AppColors.muted, size: 21),
            SizedBox(width: 10),
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
                            fontWeight: FontWeight.w600,
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
    return Semantics(
      container: true,
      label: offline
          ? 'Monitoring outage. No recent data.'
          : 'Monitoring reporting normally. Recent data received.',
      child: _DetailSurface(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: (offline ? AppColors.offline : AppColors.teal)
                    .withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                offline ? LucideIcons.wifiOff : LucideIcons.radio,
                color: offline ? AppColors.offline : AppColors.tealDark,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
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
                            fontWeight: FontWeight.w600,
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
                        : 'Recent data received for this tank.',
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
      onTap: onTap,
      label:
          'Open equipment for ${tank.name}. ${tank.equipmentCount} connected devices.',
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: const ValueKey('tank-equipment-entry'),
            borderRadius: BorderRadius.circular(17),
            onTap: onTap,
            child: Ink(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.9),
                border: Border.all(color: AppColors.line),
                borderRadius: BorderRadius.circular(17),
              ),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: AppColors.mint,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      LucideIcons.slidersHorizontal,
                      color: AppColors.tealDark,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Equipment',
                          style: TextStyle(
                            color: AppColors.text,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${tank.equipmentCount} connected devices',
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    LucideIcons.chevronRight,
                    color: AppColors.tealDark,
                    size: 19,
                  ),
                ],
              ),
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
      return const _DetailSurface(
        child: Row(
          children: [
            Icon(LucideIcons.history, color: AppColors.muted, size: 19),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'No recent activity',
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Semantics(
      container: true,
      label: '${activities.length} recent activities',
      child: Column(
        children: [
          for (var index = 0; index < activities.length; index++)
            _ActivityTimelineRow(
              activity: activities[index],
              isLast: index == activities.length - 1,
            ),
        ],
      ),
    );
  }
}

class _ActivityTimelineRow extends StatelessWidget {
  const _ActivityTimelineRow({required this.activity, required this.isLast});

  final TankActivity activity;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '${activity.title}, ${activity.detail}, ${activity.timeLabel}',
      child: ExcludeSemantics(
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 25,
                child: Column(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      margin: const EdgeInsets.only(top: 3),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.tealDark.withValues(alpha: 0.72),
                          width: 2,
                        ),
                      ),
                    ),
                    if (!isLast)
                      Expanded(
                        child: Container(
                          width: 1.5,
                          margin: const EdgeInsets.only(top: 4),
                          color: AppColors.teal.withValues(alpha: 0.24),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(bottom: isLast ? 0 : 15),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              activity.title,
                              style: const TextStyle(
                                color: AppColors.text,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              activity.detail,
                              style: const TextStyle(
                                color: AppColors.muted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        activity.timeLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

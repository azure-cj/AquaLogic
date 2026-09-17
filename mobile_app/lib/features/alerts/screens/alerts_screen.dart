import 'package:aqualogic/app/theme/app_colors.dart';
import 'package:aqualogic/app/theme/app_tokens.dart';
import 'package:aqualogic/features/alerts/data/mock_alert_repository.dart';
import 'package:aqualogic/features/alerts/models/alert_info.dart';
import 'package:aqualogic/features/alerts/screens/alert_detail_screen.dart';
import 'package:aqualogic/features/alerts/widgets/alert_tile.dart';
import 'package:aqualogic/features/alerts/widgets/alerts_header.dart';
import 'package:aqualogic/features/sensors/models/sensor_snapshot.dart';
import 'package:aqualogic/shared/widgets/app_page.dart';
import 'package:aqualogic/shared/widgets/semantic_status_widgets.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

enum AlertStream { waterQuality, monitoring }

enum AlertView { active, history }

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({
    super.key,
    required this.snapshot,
    this.repository,
    this.initialReferenceId,
    this.initialStream = AlertStream.waterQuality,
  });

  final SensorSnapshot snapshot;
  final AlertRepository? repository;
  final String? initialReferenceId;
  final AlertStream initialStream;

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  late final AlertRepository _repository =
      widget.repository ?? const MockAlertRepository();
  late AlertStream _stream;
  var _view = AlertView.active;
  final _handledIds = <String>{};
  var _didResolveInitialReference = false;
  String? _focusedMonitoringId;
  String? _referenceMessage;

  @override
  void initState() {
    super.initState();
    _stream = widget.initialStream;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resolveInitialReference();
    });
  }

  @override
  Widget build(BuildContext context) {
    final data = _repository.load(snapshot: widget.snapshot);
    final waterQuality = _waterQualityItems(data)
        .map(
          (alert) => _handledIds.contains(alert.id)
              ? alert.copyWith(lifecycle: AlertLifecycle.handled)
              : alert,
        )
        .toList(growable: false);
    final monitoring = _monitoringItems(data);
    final activeWaterCount = waterQuality
        .where((alert) => alert.isActive)
        .length;
    final criticalCount = waterQuality
        .where(
          (alert) => alert.isActive && alert.severity == AlertSeverity.critical,
        )
        .length;
    final warningCount = waterQuality
        .where(
          (alert) => alert.isActive && alert.severity == AlertSeverity.warning,
        )
        .length;
    final activeMonitoringCount = monitoring
        .where((incident) => incident.isActive)
        .length;

    return Scaffold(
      // Alerts is rendered both inside the authenticated shell and as a
      // standalone exact-context route. Keep the page's Material surface
      // local so the latter does not fall back to Flutter's red/yellow
      // missing-Material diagnostic text style or a black route background.
      backgroundColor: AppColors.background,
      body: AppPage(
        bottomClearance: AppSpacing.bottomDockClearance,
        header: const AlertsHeader(
          title: 'Alerts',
          subtitle: 'Operational issues across your fleet',
        ),
        children: [
          _AlertSummary(
            criticalCount: criticalCount,
            warningCount: warningCount,
            monitoringCount: activeMonitoringCount,
          ),
          if (_referenceMessage != null)
            Semantics(
              liveRegion: true,
              child: Text(
                _referenceMessage!,
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          _AlertStreamSelector(
            selected: _stream,
            waterQualityCount: activeWaterCount,
            monitoringCount: activeMonitoringCount,
            onSelected: (value) => setState(() => _stream = value),
          ),
          _AlertStateTabs(
            selected: _view,
            onSelected: (value) => setState(() => _view = value),
          ),
          if (_stream == AlertStream.waterQuality)
            _WaterQualityList(
              alerts: _view == AlertView.active
                  ? waterQuality
                        .where((alert) => alert.isActive)
                        .toList(growable: false)
                  : waterQuality
                        .where((alert) => !alert.isActive)
                        .toList(growable: false),
              showHistory: _view == AlertView.history,
              onOpen: _openAlert,
              onMarkHandled: _confirmMarkHandled,
            )
          else
            _MonitoringList(
              incidents: _view == AlertView.active
                  ? monitoring
                        .where((incident) => incident.isActive)
                        .toList(growable: false)
                  : monitoring
                        .where((incident) => !incident.isActive)
                        .toList(growable: false),
              showHistory: _view == AlertView.history,
              focusedId: _focusedMonitoringId,
              onOpen: _openMonitoring,
            ),
        ],
      ),
    );
  }

  List<AlertInfo> _waterQualityItems(AlertCenterData data) {
    return data.waterQualityAlerts;
  }

  List<MonitoringIncident> _monitoringItems(AlertCenterData data) {
    return data.monitoringIncidents;
  }

  void _resolveInitialReference() {
    final referenceId = widget.initialReferenceId;
    if (!mounted || referenceId == null || _didResolveInitialReference) return;

    final data = _repository.load(snapshot: widget.snapshot);
    for (final alert in data.waterQualityAlerts) {
      if (alert.id == referenceId) {
        _didResolveInitialReference = true;
        setState(() {
          _stream = AlertStream.waterQuality;
          _view = alert.isActive ? AlertView.active : AlertView.history;
        });
        _openAlert(alert);
        return;
      }
    }

    for (final incident in data.monitoringIncidents) {
      if (incident.id == referenceId) {
        _didResolveInitialReference = true;
        setState(() {
          _stream = AlertStream.monitoring;
          _view = incident.isActive ? AlertView.active : AlertView.history;
          _focusedMonitoringId = incident.id;
        });
        return;
      }
    }

    _didResolveInitialReference = true;
    setState(() {
      _referenceMessage = widget.initialStream == AlertStream.monitoring
          ? 'This monitoring incident is no longer available.'
          : 'This alert is no longer available.';
    });
  }

  Future<void> _confirmMarkHandled(AlertInfo alert) async {
    final shouldMark = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark this alert as handled?'),
        content: const Text(
          'This removes it from active alerts. It does not confirm that the water condition has returned to normal.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Mark handled'),
          ),
        ],
      ),
    );
    if (!mounted || shouldMark != true) return;
    setState(() => _handledIds.add(alert.id));
  }

  void _openAlert(AlertInfo alert) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => AlertDetailScreen(
          alert: alert,
          onMarkHandled: alert.isActive
              ? () {
                  Navigator.of(context).pop();
                  _confirmMarkHandled(alert);
                }
              : null,
        ),
      ),
    );
  }

  void _openMonitoring(MonitoringIncident incident) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => AlertsScreen(
          snapshot: widget.snapshot,
          repository: _repository,
          initialReferenceId: incident.id,
          initialStream: AlertStream.monitoring,
        ),
      ),
    );
  }
}

class _WaterQualityList extends StatelessWidget {
  const _WaterQualityList({
    required this.alerts,
    required this.showHistory,
    required this.onOpen,
    required this.onMarkHandled,
  });

  final List<AlertInfo> alerts;
  final bool showHistory;
  final ValueChanged<AlertInfo> onOpen;
  final ValueChanged<AlertInfo> onMarkHandled;

  @override
  Widget build(BuildContext context) {
    if (alerts.isEmpty) {
      return EmptyState(
        title: showHistory
            ? 'No alert history yet.'
            : 'No active water-quality alerts.',
        message: showHistory
            ? 'Resolved water-quality records will appear here.'
            : 'No current parameter conditions need acknowledgement.',
        icon: showHistory ? LucideIcons.history : LucideIcons.circleCheck,
      );
    }
    return Column(
      children: [
        for (var index = 0; index < alerts.length; index++) ...[
          if (showHistory)
            AlertHistoryRow(
              alert: alerts[index],
              onTap: () => onOpen(alerts[index]),
            )
          else
            AlertTile(
              alert: alerts[index],
              onTap: () => onOpen(alerts[index]),
              onMarkHandled: () => onMarkHandled(alerts[index]),
            ),
          if (index < alerts.length - 1) const SizedBox(height: 9),
        ],
      ],
    );
  }
}

class _MonitoringList extends StatelessWidget {
  const _MonitoringList({
    required this.incidents,
    required this.showHistory,
    required this.onOpen,
    this.focusedId,
  });

  final List<MonitoringIncident> incidents;
  final bool showHistory;
  final String? focusedId;
  final ValueChanged<MonitoringIncident> onOpen;

  @override
  Widget build(BuildContext context) {
    if (incidents.isEmpty) {
      return EmptyState(
        title: showHistory ? 'No alert history yet.' : 'No monitoring outages.',
        message: showHistory
            ? 'Recovered reporting interruptions will appear here.'
            : 'All monitored tanks are currently reporting.',
        icon: showHistory ? LucideIcons.history : LucideIcons.radio,
      );
    }
    return Column(
      children: [
        for (var index = 0; index < incidents.length; index++) ...[
          MonitoringIncidentTile(
            key: ValueKey('monitoring-incident-${incidents[index].id}'),
            incident: incidents[index],
            highlighted: focusedId == incidents[index].id,
            onTap: () => onOpen(incidents[index]),
          ),
          if (index < incidents.length - 1) const SizedBox(height: 9),
        ],
      ],
    );
  }
}

class _AlertStreamSelector extends StatelessWidget {
  const _AlertStreamSelector({
    required this.selected,
    required this.waterQualityCount,
    required this.monitoringCount,
    required this.onSelected,
  });

  final AlertStream selected;
  final int waterQualityCount;
  final int monitoringCount;
  final ValueChanged<AlertStream> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('alert-stream-selector'),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.68),
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Expanded(
            child: _AlertStreamOption(
              stream: AlertStream.waterQuality,
              label: 'Water quality',
              count: waterQualityCount,
              icon: LucideIcons.droplets,
              selected: selected == AlertStream.waterQuality,
              onTap: () => onSelected(AlertStream.waterQuality),
            ),
          ),
          Expanded(
            child: _AlertStreamOption(
              stream: AlertStream.monitoring,
              label: 'Monitoring',
              count: monitoringCount,
              icon: LucideIcons.radio,
              selected: selected == AlertStream.monitoring,
              onTap: () => onSelected(AlertStream.monitoring),
            ),
          ),
        ],
      ),
    );
  }
}

class _AlertStreamOption extends StatelessWidget {
  const _AlertStreamOption({
    required this.stream,
    required this.label,
    required this.count,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final AlertStream stream;
  final String label;
  final int count;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label:
          '$label, $count active ${stream == AlertStream.monitoring ? 'incidents' : 'alerts'}',
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          key: ValueKey('alert-stream-${stream.name}'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 11),
            decoration: BoxDecoration(
              color: selected ? AppColors.mint : Colors.transparent,
              border: Border.all(
                color: selected
                    ? AppColors.teal.withValues(alpha: 0.28)
                    : Colors.transparent,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final stacked =
                    constraints.maxWidth < 155 ||
                    MediaQuery.textScalerOf(context).scale(1) > 1.4;
                final iconWidget = Icon(
                  icon,
                  size: 19,
                  color: selected ? AppColors.tealDark : AppColors.muted,
                );
                final labelWidget = Flexible(
                  child: Text(
                    label,
                    maxLines: stacked ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: stacked ? TextAlign.center : TextAlign.start,
                    style: TextStyle(
                      color: selected ? AppColors.text : AppColors.muted,
                      fontSize: 12,
                      height: 1.15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
                final countWidget = _CountBadge(
                  count: count,
                  selected: selected,
                );
                if (stacked) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          iconWidget,
                          const SizedBox(width: 6),
                          countWidget,
                        ],
                      ),
                      const SizedBox(height: 4),
                      labelWidget,
                    ],
                  );
                }
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    iconWidget,
                    const SizedBox(width: 7),
                    labelWidget,
                    const SizedBox(width: 7),
                    countWidget,
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count, required this.selected});

  final int count;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 27, minHeight: 27),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected
            ? AppColors.teal.withValues(alpha: 0.13)
            : AppColors.line.withValues(alpha: 0.55),
        shape: BoxShape.circle,
      ),
      child: Text(
        '$count',
        key: ValueKey('alert-count-$count-${selected ? 'selected' : 'quiet'}'),
        style: TextStyle(
          color: selected ? AppColors.tealDark : AppColors.muted,
          fontSize: 11,
          height: 1,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _AlertStateTabs extends StatelessWidget {
  const _AlertStateTabs({required this.selected, required this.onSelected});

  final AlertView selected;
  final ValueChanged<AlertView> onSelected;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Alert state filter',
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 270),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SizedBox(
                width: constraints.maxWidth,
                child: Container(
                  key: const ValueKey('alert-state-tabs'),
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.55),
                    border: Border.all(color: AppColors.line),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _AlertStateOption(
                          view: AlertView.active,
                          selected: selected == AlertView.active,
                          onTap: () => onSelected(AlertView.active),
                        ),
                      ),
                      Expanded(
                        child: _AlertStateOption(
                          view: AlertView.history,
                          selected: selected == AlertView.history,
                          onTap: () => onSelected(AlertView.history),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _AlertStateOption extends StatelessWidget {
  const _AlertStateOption({
    required this.view,
    required this.selected,
    required this.onTap,
  });

  final AlertView view;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = view == AlertView.active ? 'Active' : 'History';
    return Semantics(
      button: true,
      selected: selected,
      label: '$label alerts',
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          key: ValueKey('alert-state-${view.name}'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(11),
          child: AnimatedContainer(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 140),
            constraints: const BoxConstraints(minHeight: 38),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? AppColors.mint.withValues(alpha: 0.82) : null,
              borderRadius: BorderRadius.circular(11),
              border: selected
                  ? Border.all(color: AppColors.teal.withValues(alpha: 0.16))
                  : null,
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? AppColors.text : AppColors.muted,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AlertSummary extends StatelessWidget {
  const _AlertSummary({
    required this.criticalCount,
    required this.warningCount,
    required this.monitoringCount,
  });

  final int criticalCount;
  final int warningCount;
  final int monitoringCount;

  @override
  Widget build(BuildContext context) {
    final summary =
        '$criticalCount Critical, $warningCount Warning, $monitoringCount Monitoring';
    return Semantics(
      container: true,
      label: summary,
      child: Container(
        key: const ValueKey('alert-summary-strip'),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: AppColors.line),
          borderRadius: BorderRadius.circular(17),
        ),
        child: Row(
          children: [
            Expanded(
              child: _SummaryItem(
                count: criticalCount,
                label: 'Critical',
                color: AppColors.critical,
              ),
            ),
            const _MetricDivider(),
            Expanded(
              child: _SummaryItem(
                count: warningCount,
                label: 'Warning',
                color: AppColors.warning,
              ),
            ),
            const _MetricDivider(),
            Expanded(
              child: _SummaryItem(
                count: monitoringCount,
                label: 'Monitoring',
                color: AppColors.offline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  const _SummaryItem({
    required this.count,
    required this.label,
    required this.color,
  });

  final int count;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        children: [
          Text(
            '$count',
            key: ValueKey('alert-summary-count-${label.toLowerCase()}'),
            style: TextStyle(
              color: color,
              fontSize: 22,
              height: 1.05,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 11,
              height: 1.1,
              fontWeight: FontWeight.w600,
            ),
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
      height: 42,
      child: VerticalDivider(
        width: 1,
        thickness: 1,
        color: AppColors.line.withValues(alpha: 0.95),
      ),
    );
  }
}

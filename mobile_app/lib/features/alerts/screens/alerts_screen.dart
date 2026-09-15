import 'package:aqualogic/app/theme/app_colors.dart';
import 'package:aqualogic/features/alerts/data/mock_alert_repository.dart';
import 'package:aqualogic/features/alerts/models/alert_info.dart';
import 'package:aqualogic/features/alerts/screens/alert_detail_screen.dart';
import 'package:aqualogic/features/alerts/widgets/alert_tile.dart';
import 'package:aqualogic/features/sensors/models/sensor_snapshot.dart';
import 'package:aqualogic/shared/widgets/app_page.dart';
import 'package:aqualogic/shared/widgets/header_panel.dart';
import 'package:aqualogic/shared/widgets/semantic_status_widgets.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

enum AlertStream { waterQuality, monitoring }

enum AlertView { active, history }

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key, required this.snapshot, this.repository});

  final SensorSnapshot snapshot;
  final AlertRepository? repository;

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  late final AlertRepository _repository =
      widget.repository ?? const MockAlertRepository();
  var _stream = AlertStream.waterQuality;
  var _view = AlertView.active;
  final _handledIds = <String>{};

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

    return AppPage(
      header: const HeaderPanel(
        compact: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 8),
            Text(
              'Alerts',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
            SizedBox(height: 3),
            Text(
              'Water quality and reporting state',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      ),
      children: [
        _AlertSummary(
          criticalCount: criticalCount,
          warningCount: warningCount,
          monitoringCount: activeMonitoringCount,
        ),
        _SegmentControl<AlertStream>(
          selected: _stream,
          onSelected: (value) => setState(() => _stream = value),
          segments: const [
            ButtonSegment<AlertStream>(
              value: AlertStream.waterQuality,
              label: Text('Water quality'),
              icon: Icon(LucideIcons.testTube),
            ),
            ButtonSegment<AlertStream>(
              value: AlertStream.monitoring,
              label: Text('Monitoring'),
              icon: Icon(LucideIcons.radio),
            ),
          ],
        ),
        _SegmentControl<AlertView>(
          selected: _view,
          onSelected: (value) => setState(() => _view = value),
          segments: const [
            ButtonSegment<AlertView>(
              value: AlertView.active,
              label: Text('Active'),
            ),
            ButtonSegment<AlertView>(
              value: AlertView.history,
              label: Text('History'),
            ),
          ],
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
          ),
        if (_stream == AlertStream.waterQuality)
          Text(
            '$activeWaterCount active water-quality alert${activeWaterCount == 1 ? '' : 's'}',
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
      ],
    );
  }

  List<AlertInfo> _waterQualityItems(AlertCenterData data) {
    return data.waterQualityAlerts;
  }

  List<MonitoringIncident> _monitoringItems(AlertCenterData data) {
    return data.monitoringIncidents;
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
            ? 'No handled water-quality alerts'
            : 'No active water-quality alerts',
        message: showHistory
            ? 'Handled alerts will remain available here for context.'
            : 'No current parameter conditions need acknowledgement.',
        icon: showHistory ? LucideIcons.history : LucideIcons.circleCheck,
      );
    }
    return Column(
      children: [
        for (var index = 0; index < alerts.length; index++) ...[
          AlertTile(
            alert: alerts[index],
            onTap: () => onOpen(alerts[index]),
            onMarkHandled: showHistory
                ? null
                : () => onMarkHandled(alerts[index]),
          ),
          if (index < alerts.length - 1) const SizedBox(height: 9),
        ],
      ],
    );
  }
}

class _MonitoringList extends StatelessWidget {
  const _MonitoringList({required this.incidents, required this.showHistory});

  final List<MonitoringIncident> incidents;
  final bool showHistory;

  @override
  Widget build(BuildContext context) {
    if (incidents.isEmpty) {
      return EmptyState(
        title: showHistory
            ? 'No historical monitoring outages'
            : 'No active monitoring outages',
        message: showHistory
            ? 'Recovered reporting interruptions will appear here.'
            : 'All monitored tanks are currently reporting.',
        icon: showHistory ? LucideIcons.history : LucideIcons.radio,
      );
    }
    return Column(
      children: [
        for (var index = 0; index < incidents.length; index++) ...[
          MonitoringIncidentTile(incident: incidents[index]),
          if (index < incidents.length - 1) const SizedBox(height: 9),
        ],
      ],
    );
  }
}

class _SegmentControl<T> extends StatelessWidget {
  const _SegmentControl({
    required this.selected,
    required this.onSelected,
    required this.segments,
  });

  final T selected;
  final ValueChanged<T> onSelected;
  final List<ButtonSegment<T>> segments;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SegmentedButton<T>(
        segments: segments,
        selected: {selected},
        onSelectionChanged: (selection) => onSelected(selection.first),
        showSelectedIcon: false,
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(0, 46)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 10),
          ),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
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
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(17),
      ),
      child: Row(
        children: [
          _SummaryItem(
            count: criticalCount,
            label: 'critical',
            color: AppColors.critical,
          ),
          _SummaryItem(
            count: warningCount,
            label: 'warning',
            color: AppColors.warning,
          ),
          _SummaryItem(
            count: monitoringCount,
            label: 'monitoring outages',
            color: AppColors.offline,
          ),
        ],
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
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$count $label',
            style: TextStyle(
              color: color,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

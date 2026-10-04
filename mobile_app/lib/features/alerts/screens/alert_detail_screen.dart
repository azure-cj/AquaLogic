import 'dart:async';
import 'package:aqualogic/features/alerts/models/alert_context.dart';
import 'package:aqualogic/app/theme/app_colors.dart';
import 'package:aqualogic/features/alerts/data/alert_mutation_service.dart';
import 'package:aqualogic/features/alerts/data/mock_alert_repository.dart';
import 'package:aqualogic/features/alerts/models/alert_info.dart';
import 'package:aqualogic/features/alerts/widgets/alert_tile.dart';
import 'package:aqualogic/features/alerts/widgets/alerts_header.dart';
import 'package:aqualogic/features/sensors/models/sensor_snapshot.dart';
import 'package:aqualogic/features/tanks/widgets/tank_visuals.dart';
import 'package:aqualogic/shared/formatters/local_timestamps.dart';
import 'package:aqualogic/shared/network/api_failure.dart';
import 'package:aqualogic/shared/widgets/app_page.dart';
import 'package:aqualogic/shared/widgets/semantic_status_widgets.dart';
import 'package:aqualogic/shared/widgets/soft_card.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class AlertDetailScreen extends StatefulWidget {
  const AlertDetailScreen({
    super.key,
    required this.alert,
    required this.snapshot,
    this.repository,
    this.onAlertResolved,
    this.onOpenTank,
    this.onOpenEquipment,
  });

  final AlertInfo alert;
  final SensorSnapshot snapshot;
  final AlertRepository? repository;
  final ValueChanged<AlertInfo>? onAlertResolved;
  final ValueChanged<String>? onOpenTank;
  final ValueChanged<String>? onOpenEquipment;

  @override
  State<AlertDetailScreen> createState() => _AlertDetailScreenState();
}

class _AlertDetailScreenState extends State<AlertDetailScreen> {
  late AlertInfo _alert = widget.alert;
  ApiFailure? _resolveFailure;
  bool _resolving = false;
  AlertContext? _context;
  bool _contextLoading = false;
  bool _contextFailed = false;
  int _contextRequest = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_loadContext());
  }

  Future<void> _loadContext() async {
    final repository = widget.repository;
    if (repository == null) return;
    final request = ++_contextRequest;
    setState(() {
      _contextLoading = true;
      _contextFailed = false;
    });
    try {
      final detail = await repository.loadAlertContext(
        alertId: _alert.id,
        snapshot: widget.snapshot,
      );
      if (!mounted || request != _contextRequest) return;
      final lifecycleChanged = _alert.isActive && !detail.alert.isActive;
      setState(() {
        _context = detail;
        _alert = detail.alert;
        _contextLoading = false;
      });
      if (lifecycleChanged) widget.onAlertResolved?.call(detail.alert);
    } catch (_) {
      if (!mounted || request != _contextRequest) return;
      setState(() {
        _contextFailed = true;
        _contextLoading = false;
      });
    }
  }

  @override
  void didUpdateWidget(covariant AlertDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.alert.id != widget.alert.id) {
      _alert = widget.alert;
      _resolveFailure = null;
      _resolving = false;
      _context = null;
      unawaited(_loadContext());
    }
  }

  @override
  Widget build(BuildContext context) {
    final repository = widget.repository;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        top: false,
        child: AppPage(
          header: AlertsHeader(
            title: 'Alert detail',
            subtitle: 'Review the condition and its current state',
            onBack: () => Navigator.of(context).maybePop(),
          ),
          children: [
            SoftCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      AlertSeverityPill(severity: _alert.severity),
                      const Spacer(),
                      _StateLabel(alert: _alert),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      TankIdentityMarker(
                        initial: _tankInitial(_alert.tankName),
                        size: 54,
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Text(
                          _alert.tankName,
                          style: const TextStyle(
                            color: AppColors.text,
                            fontSize: 21,
                            height: 1.1,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _alert.parameter,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 15),
                  Text(
                    _alert.message,
                    style: const TextStyle(
                      color: AppColors.text,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _AlertInfoRow(
                    label: 'Created',
                    value: _alert.startedAt == null
                        ? _alert.startedLabel
                        : formatLocalTimestamp(_alert.startedAt!),
                    icon: LucideIcons.clock3,
                  ),
                  if (_alert.resolvedAt != null) ...[
                    const Divider(height: 1),
                    _AlertInfoRow(
                      label: _alert.statusLabel,
                      value: formatLocalTimestamp(_alert.resolvedAt!),
                      icon:
                          _alert.resolutionSource ==
                              AlertResolutionSource.operator
                          ? LucideIcons.userRoundCheck
                          : LucideIcons.circleCheck,
                    ),
                  ],
                  if (_alert.resolutionSource ==
                      AlertResolutionSource.operator) ...[
                    const Divider(height: 1),
                    const _AlertInfoRow(
                      label: 'Resolution source',
                      value: 'Operator acknowledgement',
                      icon: LucideIcons.userRound,
                    ),
                  ] else if (_alert.resolutionSource ==
                      AlertResolutionSource.system) ...[
                    const Divider(height: 1),
                    const _AlertInfoRow(
                      label: 'Resolution source',
                      value: 'Automatic backend resolution',
                      icon: LucideIcons.workflow,
                    ),
                  ],
                  if (_alert.recommendation != null && _alert.isActive) ...[
                    const Divider(height: 1),
                    _AlertInfoRow(
                      label: 'Suggested follow-up',
                      value: _alert.recommendation!,
                      icon: LucideIcons.notebookPen,
                    ),
                  ],
                ],
              ),
            ),
            if (_contextLoading) const LinearProgressIndicator(),
            if (_contextFailed)
              SoftCard(
                child: Column(
                  children: [
                    const Text('Alert context could not be loaded.'),
                    TextButton(
                      onPressed: _loadContext,
                      child: const Text('Retry context'),
                    ),
                  ],
                ),
              ),
            if (!_contextFailed && _context != null)
              _ContextCard(detail: _context!),
            if (widget.onOpenTank != null)
              OutlinedButton(
                onPressed: () => widget.onOpenTank!(_alert.tankId),
                child: const Text('View tank'),
              ),
            if (widget.onOpenEquipment != null &&
                _context?.tankLifecycle == 'active')
              OutlinedButton(
                onPressed: () => widget.onOpenEquipment!(_alert.tankId),
                child: const Text('View equipment'),
              ),
            if (_resolveFailure != null)
              _ResolveFailureNotice(failure: _resolveFailure!),
            if (_alert.isActive &&
                repository != null &&
                _context?.tankLifecycle != 'retired')
              FilledButton.icon(
                key: const ValueKey('alert-detail-mark-handled'),
                onPressed:
                    _resolving ||
                        _contextLoading ||
                        (_contextFailed && repository.isLiveData)
                    ? null
                    : _confirmAndResolve,
                icon: _resolving
                    ? const SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(LucideIcons.check),
                label: Text(_resolving ? 'Saving' : 'Mark handled'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                ),
              ),
            EmptyState(
              title: _alert.isActive
                  ? 'Handling is an acknowledgement'
                  : _alert.statusLabel,
              message: _alert.isActive
                  ? 'Mark handled removes this item from the active list. It does not confirm that the water condition has returned to normal.'
                  : _alert.lifecycle == AlertLifecycle.handled
                  ? 'An operator marked this alert handled. This acknowledges a response and does not confirm that the water condition recovered.'
                  : _alert.lifecycle == AlertLifecycle.resolvedAutomatically
                  ? 'The backend resolved this alert automatically, possibly after a normal reading or threshold disabling. This does not indicate an operator marked it handled and does not confirm water recovery.'
                  : 'The backend reports this alert as resolved. No additional resolution detail is available.',
              icon: _alert.isActive
                  ? LucideIcons.info
                  : LucideIcons.circleCheck,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmAndResolve() async {
    final repository = widget.repository;
    if (repository == null || !_alert.isActive || _resolving) return;
    final shouldResolve = await showDialog<bool>(
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
    if (!mounted || shouldResolve != true) return;
    setState(() {
      _resolving = true;
      _resolveFailure = null;
    });
    final outcome = await markAlertHandled(
      repository: repository,
      snapshot: widget.snapshot,
      alert: _alert,
    );
    if (!mounted) return;
    if (outcome.isResolved) {
      final resolvedAlert = outcome.alert!;
      setState(() {
        _alert = resolvedAlert;
        _resolving = false;
        _resolveFailure = null;
      });
      widget.onAlertResolved?.call(resolvedAlert);
      await _loadContext();
      return;
    }
    setState(() {
      _resolveFailure =
          outcome.failure ??
          const ApiFailure(
            kind: ApiFailureKind.unknown,
            message: 'The alert remains active. Refresh and try again.',
            retryable: true,
          );
      _resolving = false;
    });
  }
}

class _ResolveFailureNotice extends StatelessWidget {
  const _ResolveFailureNotice({required this.failure});

  final ApiFailure failure;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('alert-resolution-failure'),
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: AppColors.line),
      borderRadius: BorderRadius.circular(15),
    ),
    child: Row(
      children: [
        const Icon(LucideIcons.cloudAlert, color: AppColors.offline, size: 19),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            failure.message,
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 11,
              height: 1.3,
            ),
          ),
        ),
      ],
    ),
  );
}

class _StateLabel extends StatelessWidget {
  const _StateLabel({required this.alert});

  final AlertInfo alert;

  @override
  Widget build(BuildContext context) {
    final color = alert.isActive
        ? alert.severity == AlertSeverity.critical
              ? AppColors.critical
              : AppColors.warning
        : alert.lifecycle == AlertLifecycle.handled
        ? AppColors.muted
        : AppColors.tealDark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color.withValues(alpha: 0.65)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        alert.statusLabel,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _AlertInfoRow extends StatelessWidget {
  const _AlertInfoRow({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppColors.muted),
        const SizedBox(width: 9),
        SizedBox(
          width: 104,
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 11,
              height: 1.3,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

String _tankInitial(String tankName) {
  final trimmed = tankName.trim();
  return trimmed.isEmpty ? '?' : trimmed.substring(0, 1).toUpperCase();
}

class _ContextCard extends StatelessWidget {
  const _ContextCard({required this.detail});
  final AlertContext detail;

  Widget _reading(String label, AlertContextReading? reading) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
      Text(
        reading == null
            ? 'Reading unavailable.'
            : '${reading.value ?? 'Unavailable'} ${reading.unit} • Reading #${reading.id}',
      ),
      if (reading != null)
        Text(
          'Observed ${formatLocalTimestamp(reading.observedAt)}\nReceived ${formatLocalTimestamp(reading.receivedAt)}',
        ),
      const SizedBox(height: 12),
    ],
  );
  Widget _bounds(String label, AlertContextThreshold? threshold) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
      Text(
        threshold == null
            ? 'Bounds unavailable.'
            : '${threshold.source == 'tank' ? 'Tank override' : 'Global default'} • ${threshold.enabled ? 'Enabled' : 'Currently disabled'}\nWarning bounds: ${threshold.warningMin ?? 'No lower bound'} – ${threshold.warningMax ?? 'No upper bound'} ${threshold.unit}\nCritical bounds: ${threshold.criticalMin ?? 'No lower bound'} – ${threshold.criticalMax ?? 'No upper bound'} ${threshold.unit}',
      ),
      const SizedBox(height: 12),
    ],
  );
  @override
  Widget build(BuildContext context) => SoftCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Tank ${detail.tankLifecycle}'),
        _reading('Reading linked to this alert', detail.linkedReading),
        _bounds('Associated historical bounds', detail.linkedThreshold),
        const Text(
          'Historical bounds are reconstructed at receipt time, not an immutable detection snapshot. Active alerts can link to subsequent abnormal readings.',
        ),
        const SizedBox(height: 12),
        _reading('Latest received reading', detail.latestReading),
        Text(
          'Reporting ${detail.latestReading?.reportingFreshness ?? 'unavailable'}. Recent receipt does not prove the observation is current.',
        ),
        const SizedBox(height: 12),
        _bounds('Current configured bounds', detail.currentThreshold),
        if (detail.speciesContext case final species?) ...[
          const Text(
            'Stored species preferences',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const Text(
            'Current assignments and latest received reading, including for historical alerts.',
          ),
          Text(
            '${species.counts['assigned']} distinct species assigned • ${species.counts['evaluable']} evaluable • ${species.counts['within']} within • ${species.counts['outside']} outside • ${species.counts['unavailable']} unavailable',
          ),
          if (species.readingId != null)
            Text(
              'Reading #${species.readingId}\nObserved ${formatLocalTimestamp(species.observedAt!)}\nReceived ${formatLocalTimestamp(species.receivedAt!)}',
            ),
          if (species.reason != null)
            Text(
              'Comparison ${species.status}: ${species.reason!.replaceAll('_', ' ')}.',
            ),
          if (species.status == 'unsupported')
            const Text(
              'Stored species preferences do not support turbidity comparisons.',
            ),
          Material(
            color: Colors.transparent,
            child: ExpansionTile(
              title: const Text('View individual stored preferences'),
              children: [
                for (final row in species.species)
                  ListTile(
                    title: Text(row.name),
                    subtitle: Text(
                      '${row.minimum ?? 'No lower bound'} – ${row.maximum ?? 'No upper bound'} ${species.unit}\n${row.result} • ${row.reason.replaceAll('_', ' ')}',
                    ),
                  ),
              ],
            ),
          ),
          Text(species.advisory),
          const SizedBox(height: 12),
        ],
        const Text(
          'Suggested checks',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        Text(detail.explanation),
        for (final check in detail.checks)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('• $check'),
          ),
        const SizedBox(height: 12),
        Text(detail.advisory),
      ],
    ),
  );
}

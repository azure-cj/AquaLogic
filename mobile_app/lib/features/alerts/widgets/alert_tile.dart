import 'package:aqualogic/app/theme/app_colors.dart';
import 'package:aqualogic/features/alerts/models/alert_info.dart';
import 'package:aqualogic/features/tanks/widgets/tank_visuals.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class AlertTile extends StatelessWidget {
  const AlertTile({
    super.key,
    required this.alert,
    this.onTap,
    this.onMarkHandled,
    this.resolving = false,
    this.resolveDisabled = false,
  });

  final AlertInfo alert;
  final VoidCallback? onTap;
  final VoidCallback? onMarkHandled;
  final bool resolving;
  final bool resolveDisabled;

  @override
  Widget build(BuildContext context) {
    final child = Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AlertHeading(alert: alert),
          const SizedBox(height: 13),
          Text(
            _compactAlertTitle(alert),
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 15,
              height: 1.25,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            '${alert.parameter} · ${alert.startedLabel}',
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 11,
              height: 1.25,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (alert.recommendation != null && alert.isActive) ...[
            const SizedBox(height: 10),
            Text(
              alert.recommendation!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 12,
                height: 1.3,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
          if (onTap != null || (alert.isActive && onMarkHandled != null)) ...[
            const SizedBox(height: 12),
            Divider(height: 1, color: AppColors.line.withValues(alpha: 0.9)),
            const SizedBox(height: 5),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 2,
                children: [
                  if (onTap != null)
                    Semantics(
                      button: true,
                      label: 'View ${alert.tankName} alert',
                      child: TextButton.icon(
                        key: ValueKey('alert-view-${alert.id}'),
                        onPressed: onTap,
                        icon: const Icon(LucideIcons.arrowUpRight, size: 17),
                        label: const Text('View alert'),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.tealDark,
                          minimumSize: const Size(44, 44),
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          textStyle: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  if (alert.isActive && onMarkHandled != null)
                    Semantics(
                      button: true,
                      label: 'Mark ${alert.tankName} alert as handled',
                      child: TextButton(
                        key: ValueKey('alert-handle-${alert.id}'),
                        onPressed: resolveDisabled ? null : onMarkHandled,
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.muted,
                          minimumSize: const Size(44, 44),
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          textStyle: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        child: resolving
                            ? const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 15,
                                    height: 15,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                  SizedBox(width: 7),
                                  Text('Saving'),
                                ],
                              )
                            : const Text('Mark handled'),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );

    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: _alertSemanticsLabel(alert),
      child: child,
    );
  }
}

class AlertHistoryRow extends StatelessWidget {
  const AlertHistoryRow({super.key, required this.alert, this.onTap});

  final AlertInfo alert;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TankIdentityMarker(initial: _tankInitial(alert.tankName), size: 42),
          const SizedBox(width: 10),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact =
                    constraints.maxWidth < 190 ||
                    MediaQuery.textScalerOf(context).scale(1) > 1.25;
                final title = Text(
                  alert.tankName,
                  maxLines: compact ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 14,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                );
                final status = _IncidentStatePill(
                  label: alert.statusLabel,
                  color: alert.lifecycle == AlertLifecycle.handled
                      ? AppColors.muted
                      : AppColors.tealDark,
                );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    compact
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              title,
                              const SizedBox(height: 5),
                              status,
                            ],
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: title),
                              const SizedBox(width: 7),
                              status,
                            ],
                          ),
                    const SizedBox(height: 4),
                    Text(
                      _compactAlertTitle(alert),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 12,
                        height: 1.25,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Water quality · ${alert.startedLabel}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 10.5,
                        height: 1.25,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 6),
            const Padding(
              padding: EdgeInsets.only(top: 15),
              child: Icon(
                LucideIcons.chevronRight,
                color: AppColors.muted,
                size: 18,
              ),
            ),
          ],
        ],
      ),
    );

    final row = Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.76),
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: content,
    );

    if (onTap == null) return row;
    return Semantics(
      button: true,
      label: 'Open ${alert.tankName} handled alert',
      child: Material(
        color: Colors.transparent,
        child: InkWell(onTap: onTap, child: row),
      ),
    );
  }
}

class MonitoringIncidentTile extends StatelessWidget {
  const MonitoringIncidentTile({
    super.key,
    required this.incident,
    this.onTap,
    this.highlighted = false,
  });

  final MonitoringIncident incident;
  final VoidCallback? onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final statusLabel = incident.lifecycleLabel;
    final statusColor = incident.isActive
        ? AppColors.offline
        : incident.resolutionReason ==
              MonitoringResolutionReason.reportingRecovered
        ? AppColors.tealDark
        : AppColors.muted;
    final timeLabel = incident.isActive
        ? incident.startedLabel
        : incident.recoveredLabel ?? incident.startedLabel;

    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TankIdentityMarker(
            initial: _tankInitial(incident.tankName),
            size: 42,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact =
                    constraints.maxWidth < 190 ||
                    MediaQuery.textScalerOf(context).scale(1) > 1.25;
                final title = Text(
                  incident.tankName,
                  maxLines: compact ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 14,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                );
                final status = _IncidentStatePill(
                  label: statusLabel,
                  color: statusColor,
                );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    compact
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              title,
                              const SizedBox(height: 5),
                              status,
                            ],
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: title),
                              const SizedBox(width: 7),
                              status,
                            ],
                          ),
                    const SizedBox(height: 4),
                    Text(
                      incident.message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 12,
                        height: 1.25,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Monitoring · $timeLabel',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 10.5,
                        height: 1.25,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 6),
            const Padding(
              padding: EdgeInsets.only(top: 15),
              child: Icon(
                LucideIcons.chevronRight,
                color: AppColors.muted,
                size: 18,
              ),
            ),
          ],
        ],
      ),
    );

    final row = Container(
      key: ValueKey('monitoring-row-${incident.id}'),
      decoration: BoxDecoration(
        color: highlighted
            ? AppColors.mint.withValues(alpha: 0.28)
            : Colors.white.withValues(alpha: 0.76),
        border: Border.all(
          color: highlighted ? AppColors.teal : AppColors.line,
          width: highlighted ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: content,
    );

    if (onTap == null) return row;
    return Semantics(
      button: true,
      label: 'Open monitoring incident for ${incident.tankName}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: row,
        ),
      ),
    );
  }
}

class AlertSeverityPill extends StatelessWidget {
  const AlertSeverityPill({super.key, required this.severity});

  final AlertSeverity severity;

  @override
  Widget build(BuildContext context) {
    final isCritical = severity == AlertSeverity.critical;
    final color = isCritical ? AppColors.critical : AppColors.warning;
    final label = isCritical ? 'Critical' : 'Warning';
    return Semantics(
      container: true,
      label: 'Alert severity $label',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          border: Border.all(color: color.withValues(alpha: 0.45)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isCritical ? LucideIcons.circleAlert : LucideIcons.triangleAlert,
              color: color,
              size: 14,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlertHeading extends StatelessWidget {
  const _AlertHeading({required this.alert});

  final AlertInfo alert;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TankIdentityMarker(initial: _tankInitial(alert.tankName), size: 50),
        const SizedBox(width: 11),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact =
                  constraints.maxWidth < 230 ||
                  MediaQuery.textScalerOf(context).scale(1) > 1.25;
              final tankName = Text(
                alert.tankName,
                maxLines: compact ? 2 : 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.text,
                  fontSize: 16,
                  height: 1.15,
                  fontWeight: FontWeight.w700,
                ),
              );
              final severity = AlertSeverityPill(severity: alert.severity);
              return compact
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [tankName, const SizedBox(height: 7), severity],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: tankName),
                        const SizedBox(width: 7),
                        severity,
                      ],
                    );
            },
          ),
        ),
      ],
    );
  }
}

class _IncidentStatePill extends StatelessWidget {
  const _IncidentStatePill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Incident status $label',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.09),
          border: Border.all(color: color.withValues(alpha: 0.38)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

String _alertSemanticsLabel(AlertInfo alert) {
  final recommendation = alert.recommendation;
  return [
    alert.tankName,
    alert.severity == AlertSeverity.critical ? 'Critical' : 'Warning',
    _compactAlertTitle(alert),
    alert.parameter,
    alert.startedLabel,
    alert.statusLabel,
    if (recommendation != null && alert.isActive) recommendation,
  ].join(', ');
}

String _compactAlertTitle(AlertInfo alert) {
  return switch (alert.message.trim()) {
    'TDS is outside the configured range.' => 'TDS outside configured range',
    'pH requires attention in the quarantine range.' => 'pH requires attention',
    _ => alert.message,
  };
}

String _tankInitial(String tankName) {
  final trimmed = tankName.trim();
  return trimmed.isEmpty ? '?' : trimmed.substring(0, 1).toUpperCase();
}

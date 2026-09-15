import 'package:aqualogic/app/theme/app_colors.dart';
import 'package:aqualogic/features/alerts/models/alert_info.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class AlertTile extends StatelessWidget {
  const AlertTile({
    super.key,
    required this.alert,
    this.onTap,
    this.onMarkHandled,
  });

  final AlertInfo alert;
  final VoidCallback? onTap;
  final VoidCallback? onMarkHandled;

  @override
  Widget build(BuildContext context) {
    final color = _severityColor(alert.severity);
    final child = Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: alert.isActive
            ? color.withValues(alpha: 0.07)
            : Colors.white.withValues(alpha: 0.72),
        border: Border.all(
          color: alert.isActive
              ? color.withValues(alpha: 0.58)
              : AppColors.line,
        ),
        borderRadius: BorderRadius.circular(17),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 19,
                backgroundColor: color.withValues(alpha: 0.13),
                child: Icon(alert.icon, color: color, size: 20),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      alert.severity.name.toUpperCase(),
                      style: TextStyle(
                        color: color,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.7,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      alert.tankName,
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      alert.parameter,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              if (onTap != null)
                const Icon(
                  LucideIcons.chevronRight,
                  color: AppColors.muted,
                  size: 18,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            alert.message,
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 12,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            '${alert.startedLabel} · ${alert.statusLabel}',
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (alert.recommendation != null && alert.isActive) ...[
            const SizedBox(height: 9),
            Text(
              'Recommended: ${alert.recommendation}',
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (alert.isActive && onMarkHandled != null) ...[
            const SizedBox(height: 9),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onMarkHandled,
                icon: const Icon(LucideIcons.check, size: 16),
                label: const Text('Mark handled'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.tealDark,
                  minimumSize: const Size(44, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                ),
              ),
            ),
          ],
        ],
      ),
    );

    if (onTap == null) return child;
    return Semantics(
      button: true,
      label: 'Open ${alert.tankName} ${alert.parameter} alert',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(17),
          child: child,
        ),
      ),
    );
  }
}

class MonitoringIncidentTile extends StatelessWidget {
  const MonitoringIncidentTile({super.key, required this.incident, this.onTap});

  final MonitoringIncident incident;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final child = Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: incident.isActive
            ? AppColors.offline.withValues(alpha: 0.07)
            : Colors.white.withValues(alpha: 0.72),
        border: Border.all(
          color: incident.isActive ? AppColors.offline : AppColors.line,
        ),
        borderRadius: BorderRadius.circular(17),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 19,
            backgroundColor: AppColors.offline.withValues(alpha: 0.13),
            child: const Icon(
              LucideIcons.wifiOff,
              color: AppColors.offline,
              size: 20,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  incident.isActive
                      ? 'MONITORING OUTAGE'
                      : 'RECOVERED MONITORING OUTAGE',
                  style: const TextStyle(
                    color: AppColors.offline,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  incident.tankName,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  incident.message,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  incident.recoveredLabel ?? incident.startedLabel,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (onTap != null)
            const Icon(
              LucideIcons.chevronRight,
              color: AppColors.muted,
              size: 18,
            ),
        ],
      ),
    );

    if (onTap == null) return child;
    return Semantics(
      button: true,
      label: 'Open monitoring incident for ${incident.tankName}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(17),
          child: child,
        ),
      ),
    );
  }
}

Color _severityColor(AlertSeverity severity) {
  return switch (severity) {
    AlertSeverity.critical => AppColors.critical,
    AlertSeverity.warning => AppColors.warning,
  };
}

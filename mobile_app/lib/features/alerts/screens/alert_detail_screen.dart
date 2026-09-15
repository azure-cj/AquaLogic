import 'package:aqualogic/app/theme/app_colors.dart';
import 'package:aqualogic/features/alerts/models/alert_info.dart';
import 'package:aqualogic/shared/widgets/app_page.dart';
import 'package:aqualogic/shared/widgets/header_panel.dart';
import 'package:aqualogic/shared/widgets/semantic_status_widgets.dart';
import 'package:aqualogic/shared/widgets/soft_card.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class AlertDetailScreen extends StatelessWidget {
  const AlertDetailScreen({super.key, required this.alert, this.onMarkHandled});

  final AlertInfo alert;
  final VoidCallback? onMarkHandled;

  @override
  Widget build(BuildContext context) {
    final color = alert.severity == AlertSeverity.critical
        ? AppColors.critical
        : AppColors.warning;
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
                  tooltip: 'Back to Alerts',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(LucideIcons.arrowLeft),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Alert detail',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const Text(
                  'Review the condition and its current state',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          children: [
            SoftCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(alert.icon, color: color, size: 23),
                      const SizedBox(width: 9),
                      Text(
                        alert.severity.name.toUpperCase(),
                        style: TextStyle(
                          color: color,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const Spacer(),
                      _StateLabel(active: alert.isActive),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    alert.tankName,
                    style: const TextStyle(
                      color: AppColors.text,
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    alert.parameter,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 15),
                  Text(
                    alert.message,
                    style: const TextStyle(
                      color: AppColors.text,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 14),
                  InfoRow(
                    label: 'Started',
                    value: alert.startedLabel,
                    icon: LucideIcons.clock3,
                  ),
                  if (alert.recommendation != null) ...[
                    const Divider(height: 1),
                    InfoRow(
                      label: 'Suggested follow-up',
                      value: alert.recommendation!,
                      icon: LucideIcons.notebookPen,
                    ),
                  ],
                ],
              ),
            ),
            if (alert.isActive && onMarkHandled != null)
              FilledButton.icon(
                onPressed: onMarkHandled,
                icon: const Icon(LucideIcons.check),
                label: const Text('Mark handled'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                ),
              ),
            const EmptyState(
              title: 'Handling is an acknowledgement',
              message:
                  'Mark handled removes this item from the active list. It does not confirm that the water condition has returned to normal.',
              icon: LucideIcons.info,
            ),
          ],
        ),
      ),
    );
  }
}

class _StateLabel extends StatelessWidget {
  const _StateLabel({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.warning : AppColors.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color.withValues(alpha: 0.65)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        active ? 'Active' : 'Handled',
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

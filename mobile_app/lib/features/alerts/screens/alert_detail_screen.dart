import 'package:aqualogic/app/theme/app_colors.dart';
import 'package:aqualogic/features/alerts/models/alert_info.dart';
import 'package:aqualogic/features/alerts/widgets/alert_tile.dart';
import 'package:aqualogic/features/alerts/widgets/alerts_header.dart';
import 'package:aqualogic/features/tanks/widgets/tank_visuals.dart';
import 'package:aqualogic/shared/widgets/app_page.dart';
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
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        top: false,
        child: AppPage(
          header: AlertsHeader(
            title: 'Alert detail',
            subtitle: 'Review the condition and its current state',
            onBack: () => Navigator.of(context).pop(),
          ),
          children: [
            SoftCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      AlertSeverityPill(severity: alert.severity),
                      const Spacer(),
                      _StateLabel(active: alert.isActive),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      TankIdentityMarker(
                        initial: _tankInitial(alert.tankName),
                        size: 54,
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Text(
                          alert.tankName,
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
                    alert.parameter,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
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
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

String _tankInitial(String tankName) {
  final trimmed = tankName.trim();
  return trimmed.isEmpty ? '?' : trimmed.substring(0, 1).toUpperCase();
}

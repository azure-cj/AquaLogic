import 'package:aqualogic/shared/widgets/light_page_header.dart';
import 'package:flutter/material.dart';

/// The light operational header shared by the Alerts list and its detail view.
class AlertsHeader extends StatelessWidget {
  const AlertsHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.onBack,
    this.backLabel = 'Back to Alerts',
  });

  final String title;
  final String subtitle;
  final VoidCallback? onBack;
  final String backLabel;

  @override
  Widget build(BuildContext context) {
    return LightPageHeader(
      title: title,
      subtitle: subtitle,
      onBack: onBack,
      backLabel: backLabel,
      titleKey: onBack == null ? const ValueKey('alerts-page-title') : null,
      motifOpacity: 0.055,
      motifStrokeWidth: 17,
    );
  }
}

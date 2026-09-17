import 'package:aqualogic/shared/widgets/light_page_header.dart';
import 'package:flutter/material.dart';

/// The quiet, light header used by the More/account hub and its destinations.
class MoreHeader extends StatelessWidget {
  const MoreHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.onBack,
    this.backLabel = 'Back to More',
    this.titleKey,
    this.bottom,
  });

  final String title;
  final String subtitle;
  final VoidCallback? onBack;
  final String backLabel;
  final Key? titleKey;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    return LightPageHeader(
      title: title,
      subtitle: subtitle,
      onBack: onBack,
      backLabel: backLabel,
      titleKey: titleKey,
      footer: bottom,
    );
  }
}

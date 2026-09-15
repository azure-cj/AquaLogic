import 'package:aqualogic/app/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class SectionTitle extends StatelessWidget {
  const SectionTitle({
    super.key,
    required this.title,
    this.action,
    this.onTap,
    this.actionArrow = false,
  });

  final String title;
  final String? action;
  final VoidCallback? onTap;
  final bool actionArrow;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (action != null)
          actionArrow
              ? TextButton.icon(
                  onPressed: onTap,
                  icon: const Icon(LucideIcons.arrowUpRight, size: 14),
                  label: Text(action!),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.tealDark,
                    minimumSize: const Size(0, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              : TextButton(
                  onPressed: onTap,
                  child: Text(action!, style: const TextStyle(fontSize: 12)),
                ),
      ],
    );
  }
}

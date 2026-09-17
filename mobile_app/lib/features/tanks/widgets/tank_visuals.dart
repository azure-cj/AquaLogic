import 'package:aqualogic/app/theme/app_colors.dart';
import 'package:aqualogic/shared/formatters/freshness_labels.dart';
import 'package:flutter/material.dart';

class TankIdentityMarker extends StatelessWidget {
  const TankIdentityMarker({super.key, required this.initial, this.size = 50});

  final String initial;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.teal.withValues(alpha: 0.09),
              ),
            ),
            Container(
              width: size * 0.82,
              height: size * 0.82,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.teal.withValues(alpha: 0.18),
                ),
              ),
            ),
            Container(
              width: size * 0.62,
              height: size * 0.62,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.mint.withValues(alpha: 0.82),
              ),
              child: Text(
                initial,
                style: TextStyle(
                  color: AppColors.tealDark,
                  fontSize: size * 0.32,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String compactFreshnessLabel(String label) {
  return formatFreshnessLabel(label);
}

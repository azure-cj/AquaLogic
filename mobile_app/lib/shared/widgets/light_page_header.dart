import 'dart:math' as math;

import 'package:aqualogic/app/theme/app_colors.dart';
import 'package:aqualogic/app/theme/app_tokens.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// The shared light header language for operational and secondary pages.
///
/// The low-contrast current motif is decorative. Feature wrappers can tune it
/// slightly when an intentional surface-specific emphasis is needed without
/// duplicating the header structure.
class LightPageHeader extends StatelessWidget {
  const LightPageHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.onBack,
    this.backLabel = 'Back',
    this.titleKey,
    this.footer,
    this.motifOpacity = 0.045,
    this.motifStrokeWidth = 15,
  });

  final String title;
  final String subtitle;
  final VoidCallback? onBack;
  final String backLabel;
  final Key? titleKey;
  final Widget? footer;
  final double motifOpacity;
  final double motifStrokeWidth;

  @override
  Widget build(BuildContext context) {
    final safeTop = MediaQuery.paddingOf(context).top;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(
        bottom: Radius.circular(AppRadii.pageHeader),
      ),
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned(
            top: -72,
            right: -58,
            width: 290,
            height: 218,
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: CustomPaint(
                  painter: _HeaderMotifPainter(
                    opacity: motifOpacity,
                    strokeWidth: motifStrokeWidth,
                  ),
                ),
              ),
            ),
          ),
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(
              AppSpacing.pageGutter,
              safeTop + 16,
              AppSpacing.pageGutter,
              21,
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: 0.66),
                  AppColors.background.withValues(alpha: 0.92),
                ],
              ),
              border: Border(
                bottom: BorderSide(
                  color: AppColors.line.withValues(alpha: 0.8),
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (onBack != null) ...[
                      IconButton(
                        tooltip: backLabel,
                        onPressed: onBack,
                        style: IconButton.styleFrom(
                          minimumSize: const Size(48, 48),
                          padding: EdgeInsets.zero,
                          foregroundColor: AppColors.tealDark,
                          backgroundColor: Colors.white.withValues(alpha: 0.72),
                          side: const BorderSide(color: AppColors.line),
                        ),
                        icon: const Icon(LucideIcons.arrowLeft),
                      ),
                      const SizedBox(width: 5),
                    ],
                    Semantics(
                      image: true,
                      label: 'AquaLogic logo',
                      child: Image.asset(
                        'assets/images/aqualogic_icon.png',
                        width: 24,
                        height: 24,
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: FittedBox(
                        alignment: Alignment.centerLeft,
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'AquaLogic',
                          style: TextStyle(
                            color: AppColors.text,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 17),
                Text(
                  title,
                  key: titleKey,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 28,
                    height: 1.05,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 13,
                    height: 1.2,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (footer != null) ...[const SizedBox(height: 14), footer!],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderMotifPainter extends CustomPainter {
  const _HeaderMotifPainter({required this.opacity, required this.strokeWidth});

  final double opacity;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    for (var index = 0; index < 4; index++) {
      paint.color = AppColors.teal.withValues(
        alpha: math.max(0, opacity - index * 0.006),
      );
      final inset = index * 24.0;
      canvas.drawArc(
        Rect.fromLTWH(
          -size.width * 0.34 + inset,
          size.height * 0.12 + inset,
          size.width * 1.42,
          size.height * 1.14,
        ),
        math.pi * 1.06,
        math.pi * 0.58,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HeaderMotifPainter oldDelegate) =>
      oldDelegate.opacity != opacity || oldDelegate.strokeWidth != strokeWidth;
}

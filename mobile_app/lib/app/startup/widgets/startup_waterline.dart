import 'dart:math' as math;

import 'package:aqualogic/app/theme/app_colors.dart';
import 'package:flutter/material.dart';

class StartupWaterline extends StatelessWidget {
  const StartupWaterline({
    super.key,
    required this.clock,
    required this.settle,
    required this.reducedMotion,
  });

  final Animation<double> clock;
  final Animation<double> settle;
  final bool reducedMotion;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: CustomPaint(
          size: const Size(140, 16),
          painter: _StartupWaterlinePainter(
            clock: clock,
            settle: settle,
            reducedMotion: reducedMotion,
          ),
        ),
      ),
    );
  }
}

class _StartupWaterlinePainter extends CustomPainter {
  _StartupWaterlinePainter({
    required this.clock,
    required this.settle,
    required this.reducedMotion,
  }) : super(repaint: Listenable.merge([clock, settle]));

  final Animation<double> clock;
  final Animation<double> settle;
  final bool reducedMotion;

  @override
  void paint(Canvas canvas, Size size) {
    final progress = reducedMotion ? 0.0 : clock.value;
    final settled = settle.value.clamp(0.0, 1.0);
    final amplitude = 1.25 * (1 - settled) * (reducedMotion ? 0.35 : 1);
    final centerY = size.height / 2;
    final angularOffset = progress * math.pi * 2;
    double yFor(double x) {
      final phase = (x / size.width * math.pi * 2) + angularOffset;
      return centerY + math.sin(phase) * amplitude;
    }

    final path = Path()..moveTo(0, yFor(0));

    for (var step = 1; step <= 56; step++) {
      final x = size.width * step / 56;
      path.lineTo(x, yFor(x));
    }

    canvas.drawLine(
      Offset(0, centerY),
      Offset(size.width, centerY),
      Paint()
        ..color = AppColors.tealDark.withValues(alpha: 0.14)
        ..strokeWidth = 1
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.tealDark.withValues(alpha: 0.62 + settled * 0.16)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    final center = Offset(size.width / 2, centerY);
    canvas.drawCircle(
      center,
      4,
      Paint()..color = AppColors.teal.withValues(alpha: 0.07 + settled * 0.08),
    );
    canvas.drawCircle(
      center,
      1.5,
      Paint()
        ..color = AppColors.tealDark.withValues(alpha: 0.72 + settled * 0.18),
    );
  }

  @override
  bool shouldRepaint(covariant _StartupWaterlinePainter oldDelegate) =>
      oldDelegate.clock != clock ||
      oldDelegate.settle != settle ||
      oldDelegate.reducedMotion != reducedMotion;
}

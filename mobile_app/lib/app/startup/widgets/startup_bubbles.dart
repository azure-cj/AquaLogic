import 'dart:math' as math;

import 'package:aqualogic/app/theme/app_colors.dart';
import 'package:flutter/material.dart';

class StartupBubbles extends StatelessWidget {
  const StartupBubbles({
    super.key,
    required this.waterlineClock,
    required this.shortClock,
    required this.mediumClock,
    required this.settle,
    required this.reducedMotion,
  });

  final Animation<double> waterlineClock;
  final Animation<double> shortClock;
  final Animation<double> mediumClock;
  final Animation<double> settle;
  final bool reducedMotion;

  @override
  Widget build(BuildContext context) {
    if (reducedMotion) return const SizedBox.shrink();

    return IgnorePointer(
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, constraints) => AnimatedBuilder(
            animation: Listenable.merge([
              waterlineClock,
              shortClock,
              mediumClock,
              settle,
            ]),
            builder: (context, child) {
              final bubbles = [
                _Bubble(
                  clock: waterlineClock,
                  phase: 0.12,
                  x: 0.19,
                  y: 0.64,
                  size: 5,
                  travel: 27,
                ),
                _Bubble(
                  clock: mediumClock,
                  phase: 0.54,
                  x: 0.82,
                  y: 0.55,
                  size: 6,
                  travel: 32,
                ),
                _Bubble(
                  clock: shortClock,
                  phase: 0.31,
                  x: 0.73,
                  y: 0.74,
                  size: 4,
                  travel: 24,
                ),
                _Bubble(
                  clock: waterlineClock,
                  phase: 0.62,
                  x: 0.27,
                  y: 0.77,
                  size: 5.5,
                  travel: 30,
                ),
              ];
              final remaining = 1 - settle.value.clamp(0.0, 1.0);

              return Stack(
                children: [
                  for (final bubble in bubbles)
                    _positionedBubble(bubble, constraints.biggest, remaining),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _positionedBubble(_Bubble bubble, Size size, double remaining) {
    final phase = (bubble.clock.value + bubble.phase) % 1;
    final visibility = math.pow(math.sin(math.pi * phase), 2).toDouble();
    final opacity = 0.20 * visibility * remaining;
    final top = size.height * bubble.y + (1 - phase) * bubble.travel;

    return Positioned(
      left: size.width * bubble.x - bubble.size / 2,
      top: top,
      child: Opacity(
        opacity: opacity,
        child: Container(
          width: bubble.size,
          height: bubble.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.teal.withValues(alpha: 0.22),
            border: Border.all(
              color: AppColors.tealDark.withValues(alpha: 0.70),
              width: 0.9,
            ),
          ),
        ),
      ),
    );
  }
}

class _Bubble {
  const _Bubble({
    required this.clock,
    required this.phase,
    required this.x,
    required this.y,
    required this.size,
    required this.travel,
  });

  final Animation<double> clock;
  final double phase;
  final double x;
  final double y;
  final double size;
  final double travel;
}

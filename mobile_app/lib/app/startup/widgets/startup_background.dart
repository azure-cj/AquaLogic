import 'package:aqualogic/app/theme/app_colors.dart';
import 'package:flutter/material.dart';

class StartupBackground extends StatelessWidget {
  const StartupBackground({super.key, required this.reducedMotion});

  final bool reducedMotion;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: AppColors.background),
        ExcludeSemantics(
          child: IgnorePointer(
            child: Image.asset(
              'assets/images/startup_underwater.png',
              key: const ValueKey('startup-background-illustration'),
              fit: BoxFit.cover,
              alignment: Alignment.bottomCenter,
              filterQuality: FilterQuality.medium,
              frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                if (wasSynchronouslyLoaded) return child;
                return AnimatedOpacity(
                  opacity: frame == null ? 0 : 1,
                  duration: reducedMotion
                      ? const Duration(milliseconds: 120)
                      : const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                  child: child,
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

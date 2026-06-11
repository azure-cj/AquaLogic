import 'package:aqualogic/app/theme/app_colors.dart';
import 'package:aqualogic/shared/models/reading_state.dart';
import 'package:flutter/material.dart';

class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    required this.state,
    this.dark = false,
  });

  final String label;
  final ReadingState state;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final color = stateColor(state);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: dark
            ? color.withValues(alpha: 0.14)
            : color.withValues(alpha: 0.16),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, color: color, size: 7),
          const SizedBox(width: 5),
          Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: dark ? Colors.white : color,
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

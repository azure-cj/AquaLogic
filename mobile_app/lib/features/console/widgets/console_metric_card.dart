import 'package:flutter/material.dart';
import 'console_style.dart';

class ConsoleMetricCard extends StatelessWidget {
  const ConsoleMetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
    required this.icon,
    required this.stale,
    this.attention = false,
  });
  final String label;
  final String value;
  final String unit;
  final IconData icon;
  final bool stale;
  final bool attention;

  @override
  Widget build(BuildContext context) {
    final color = stale
        ? ConsoleStyle.muted
        : attention
        ? ConsoleStyle.warning
        : ConsoleStyle.accent;
    return Semantics(
      label:
          '$label $value $unit. ${stale
              ? 'Last known'
              : attention
              ? 'Needs attention'
              : 'Normal'}. Simulated reading.',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: ConsoleStyle.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: attention && !stale
                ? ConsoleStyle.warning
                : ConsoleStyle.border,
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final short = constraints.maxHeight < 108;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, color: color, size: short ? 18 : 22),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          height: 1,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text.rich(
                    style: const TextStyle(height: 1),
                    TextSpan(
                      children: [
                        TextSpan(
                          text: value,
                          style: TextStyle(
                            fontSize: short ? 36 : 46,
                            fontWeight: FontWeight.w700,
                            color: stale
                                ? ConsoleStyle.muted
                                : ConsoleStyle.text,
                          ),
                        ),
                        if (unit.isNotEmpty)
                          TextSpan(
                            text: ' $unit',
                            style: const TextStyle(
                              fontSize: 17,
                              color: ConsoleStyle.muted,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  stale
                      ? 'LAST KNOWN'
                      : attention
                      ? 'ATTENTION'
                      : 'NORMAL',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                    color: stale
                        ? ConsoleStyle.muted
                        : attention
                        ? ConsoleStyle.warning
                        : ConsoleStyle.good,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'console_style.dart';

class ConsoleConnectionIndicator extends StatelessWidget {
  const ConsoleConnectionIndicator({
    super.key,
    required this.label,
    required this.connected,
    this.compact = false,
  });
  final String label;
  final bool connected;

  /// Compact shows only the dot and the label, for the console header.
  final bool compact;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: connected ? ConsoleStyle.good : ConsoleStyle.warning,
        ),
      ),
      const SizedBox(width: 8),
      Text(
        compact ? label : '$label · ${connected ? 'Connected' : 'Unavailable'}',
        semanticsLabel: '$label ${connected ? 'connected' : 'unavailable'}',
        style: TextStyle(
          fontSize: compact ? 14 : 13,
          height: 1,
          fontWeight: FontWeight.w500,
          color: connected ? ConsoleStyle.muted : ConsoleStyle.warning,
        ),
      ),
    ],
  );
}

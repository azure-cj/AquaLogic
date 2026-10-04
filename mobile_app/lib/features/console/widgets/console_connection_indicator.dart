import 'package:flutter/material.dart';
import 'console_style.dart';

class ConsoleConnectionIndicator extends StatelessWidget {
  const ConsoleConnectionIndicator({
    super.key,
    required this.label,
    required this.connected,
  });
  final String label;
  final bool connected;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        connected ? Icons.check_circle_outline : Icons.cloud_off_outlined,
        size: 17,
        color: connected ? ConsoleStyle.good : ConsoleStyle.warning,
      ),
      const SizedBox(width: 6),
      Text(
        '$label · ${connected ? 'Connected' : 'Unavailable'}',
        style: const TextStyle(
          fontSize: 12,
          height: 1,
          color: ConsoleStyle.muted,
        ),
      ),
    ],
  );
}

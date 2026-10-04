import 'package:flutter/material.dart';
import '../models/console_state.dart';
import 'console_connection_indicator.dart';

class ConsoleStatusBar extends StatelessWidget {
  const ConsoleStatusBar({super.key, required this.state});
  final ConsoleState state;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 24,
    runSpacing: 6,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      ConsoleConnectionIndicator(
        label: 'LOCAL ESP32',
        connected: state.localConnected,
      ),
      ConsoleConnectionIndicator(
        label: 'CLOUD',
        connected: state.cloudConnected,
      ),
    ],
  );
}

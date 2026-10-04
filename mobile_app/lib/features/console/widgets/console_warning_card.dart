import 'package:flutter/material.dart';
import '../models/console_state.dart';
import 'console_style.dart';

class ConsoleWarningCard extends StatelessWidget {
  const ConsoleWarningCard({
    super.key,
    required this.state,
    required this.onRetry,
  });
  final ConsoleState state;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    final offline = !state.localConnected;
    final color = offline
        ? ConsoleStyle.muted
        : switch (state.quality) {
            ConsoleWaterQuality.normal => ConsoleStyle.good,
            ConsoleWaterQuality.attention => ConsoleStyle.warning,
            ConsoleWaterQuality.critical => ConsoleStyle.critical,
          };
    final label = offline
        ? 'LOCAL DEVICE OFFLINE'
        : 'WATER QUALITY · ${state.quality.label}';
    final description = offline
        ? 'Last reading ${TimeOfDay.fromDateTime(state.observedAt).format(context)}. Controls disabled until local connection returns.'
        : switch (state.quality) {
            ConsoleWaterQuality.normal =>
              'All four simulated parameters are within the configured range.',
            ConsoleWaterQuality.attention =>
              'Simulated pH needs attention. Check the water before taking action.',
            ConsoleWaterQuality.critical =>
              'Immediate operator attention required in this simulated scenario.',
          };
    return Row(
      children: [
        Icon(
          offline
              ? Icons.wifi_off
              : state.quality == ConsoleWaterQuality.normal
              ? Icons.check_circle_outline
              : Icons.warning_amber_rounded,
          color: color,
          size: 24,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 14,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .6,
                ),
              ),
              Text(
                description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.2,
                  color: ConsoleStyle.muted,
                ),
              ),
            ],
          ),
        ),
        if (offline) TextButton(onPressed: onRetry, child: const Text('RETRY')),
      ],
    );
  }
}

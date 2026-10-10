import 'package:flutter/material.dart';
import '../models/console_state.dart';
import 'console_style.dart';

/// Water-quality verdict strip, coloured by the reported state.
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
    final offline = state.readingsStale;
    final color = offline
        ? ConsoleStyle.muted
        : switch (state.quality) {
            ConsoleWaterQuality.normal => ConsoleStyle.good,
            ConsoleWaterQuality.attention => ConsoleStyle.warning,
            ConsoleWaterQuality.critical => ConsoleStyle.critical,
            null => ConsoleStyle.muted,
          };
    final label = offline
        ? (state.connection == ConsoleLocalConnection.degraded
              ? 'Local data degraded'
              : state.connection == ConsoleLocalConnection.connecting
              ? 'Connecting to the tank controller'
              : 'Local device offline')
        : switch (state.quality) {
            ConsoleWaterQuality.normal => 'Water quality is good',
            ConsoleWaterQuality.attention => 'Water quality needs attention',
            ConsoleWaterQuality.critical => 'Water quality is critical',
            null => 'Water quality unavailable',
          };
    final description = offline
        ? (state.observedAt == null
              ? 'No valid readings received. Live controls remain disabled.'
              : 'Last received ${TimeOfDay.fromDateTime(state.observedAt!).format(context)}. Last-known data; live controls disabled.')
        : !state.isSimulated
        ? (state.quality == null
              ? 'The tank controller has not reported a water-quality status yet.'
              : _liveDescription(state))
        : switch (state.quality) {
            ConsoleWaterQuality.normal =>
              'All four simulated parameters are within the configured range.',
            ConsoleWaterQuality.attention =>
              'Simulated pH needs attention. Check the water before taking action.',
            ConsoleWaterQuality.critical =>
              'Immediate operator attention required in this simulated scenario.',
            null => 'Water quality unavailable.',
          };
    final tinted = offline || state.quality != ConsoleWaterQuality.normal;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      decoration: BoxDecoration(
        color: tinted
            ? Color.alphaBlend(
                color.withValues(alpha: .10),
                ConsoleStyle.surface,
              )
            : ConsoleStyle.surface,
        borderRadius: BorderRadius.circular(ConsoleStyle.controlRadius),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          const SizedBox(width: 20),
          Icon(
            offline
                ? Icons.wifi_off
                : state.quality == ConsoleWaterQuality.normal
                ? Icons.check_circle_outline
                : Icons.warning_amber_rounded,
            color: color,
            size: 26,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final title = Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tinted ? color : ConsoleStyle.text,
                    fontSize: 18,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                  ),
                );
                final body = Text(
                  description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.25,
                    color: ConsoleStyle.muted,
                  ),
                );
                // Wide strips read as one line; narrow ones stack.
                return constraints.maxWidth >= 720
                    ? Row(
                        children: [
                          title,
                          const SizedBox(width: 16),
                          Expanded(child: body),
                        ],
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [title, body],
                      );
              },
            ),
          ),
          if (offline)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: TextButton(onPressed: onRetry, child: const Text('Retry')),
            ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }
}

const _sensorLabels = {
  'temp': 'Temperature',
  'ph': 'pH',
  'tds': 'TDS',
  'turbidity': 'Turbidity',
};

String _liveDescription(ConsoleState state) {
  if (state.quality == ConsoleWaterQuality.normal) {
    return 'All reported readings are within the normal range.';
  }
  final flagged = [
    for (final entry in _sensorLabels.entries)
      if (state.sensorStatuses[entry.key] case final String status
          when status != 'NORMAL' && status != 'CLEAR')
        entry.value,
  ];
  final subject = switch (flagged.length) {
    0 => 'A reading is',
    1 => '${flagged.single} is',
    _ =>
      '${flagged.sublist(0, flagged.length - 1).join(', ')} and ${flagged.last} are',
  };
  return state.quality == ConsoleWaterQuality.critical
      ? '$subject at a critical level. Check the tank now and hold off on dosing.'
      : '$subject outside the normal range. Check the water before dosing.';
}

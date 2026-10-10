import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'console_style.dart';

/// One reading column. Rendered inside the shared readings slab, so it draws no
/// card chrome of its own; attention is shown by a top bar and value colour.
class ConsoleMetricCard extends StatelessWidget {
  const ConsoleMetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
    required this.icon,
    required this.stale,
    this.attention = false,
    this.critical = false,
    this.isSimulated = true,
    this.reportedStatus,
  });
  final String label;
  final String value;
  final String unit;
  final IconData icon;
  final bool stale;
  final bool attention;

  /// Simulated critical scenario; live readings use the reported status.
  final bool critical;
  final bool isSimulated;
  final String? reportedStatus;

  @override
  Widget build(BuildContext context) {
    final highlight =
        attention ||
        (!isSimulated &&
            reportedStatus != null &&
            reportedStatus != 'NORMAL' &&
            reportedStatus != 'CLEAR');
    final severe =
        highlight && (isSimulated ? critical : reportedStatus == 'CRITICAL');
    final tone = severe ? ConsoleStyle.critical : ConsoleStyle.warning;
    final statusColor =
        stale || value == '—' || (!isSimulated && reportedStatus == null)
        ? ConsoleStyle.faint
        : highlight
        ? tone
        : ConsoleStyle.good;
    final status = value == '—'
        ? 'Unavailable'
        : stale
        ? 'Last known'
        : !isSimulated
        // Firmware grades turbidity as MODERATE; show the shared scale.
        ? (reportedStatus == 'MODERATE' ? 'WARNING' : reportedStatus) ??
              'Status unknown'
        : attention && critical
        ? 'Critical'
        : attention
        ? 'Attention'
        : 'Normal';
    return Semantics(
      label:
          '$label $value $unit. $status. ${isSimulated ? 'Simulated' : 'Live'} reading.',
      child: Stack(
        children: [
          Positioned(
            left: 20,
            right: 20,
            top: 0,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              height: 3,
              decoration: BoxDecoration(
                color: highlight && !stale ? tone : Colors.transparent,
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(3),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 14, 14),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final short = constraints.maxHeight < 130;
                // Display mode gives the slab most of the screen: read across a room.
                final tall = constraints.maxHeight >= 300;
                // Columns share one width, so a width-derived size keeps every
                // value the same height instead of each one shrinking to fit.
                final valueSize = math.min(
                  short ? 40.0 : (tall ? 84.0 : 68.0),
                  constraints.maxWidth / 3.4,
                );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          icon,
                          size: short ? 16 : (tall ? 22 : 20),
                          color: stale
                              ? ConsoleStyle.faint
                              : ConsoleStyle.accent,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              height: 1,
                              fontSize: short ? 13 : (tall ? 18 : 15),
                              fontWeight: FontWeight.w600,
                              letterSpacing: .3,
                              color: ConsoleStyle.muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(flex: 2),
                    Flexible(
                      flex: 6,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.bottomLeft,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          child: Text.rich(
                            key: ValueKey('$value$stale$attention'),
                            style: TextStyle(
                              height: 1,
                              fontSize: valueSize,
                              fontWeight: FontWeight.w600,
                              letterSpacing: short ? -.8 : (tall ? -2 : -1.5),
                              fontFeatures: ConsoleStyle.tabular,
                              color: stale
                                  ? ConsoleStyle.faint
                                  : highlight
                                  ? tone
                                  : ConsoleStyle.text,
                            ),
                            TextSpan(
                              children: [
                                TextSpan(text: value),
                                if (unit.isNotEmpty)
                                  TextSpan(
                                    text: ' $unit',
                                    style: TextStyle(
                                      fontSize: short ? 15 : (tall ? 24 : 20),
                                      fontWeight: FontWeight.w500,
                                      letterSpacing: 0,
                                      color: ConsoleStyle.muted,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: short ? 8 : 14),
                    Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            status,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: short ? 12 : (tall ? 18 : 14),
                              height: 1,
                              fontWeight: FontWeight.w600,
                              color: statusColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    // Keeps the value group optically centred in tall slabs.
                    const Spacer(flex: 3),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

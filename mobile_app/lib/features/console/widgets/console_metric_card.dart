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
    this.isSimulated = true,
    this.reportedStatus,
  });
  final String label;
  final String value;
  final String unit;
  final IconData icon;
  final bool stale;
  final bool attention;
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
    final statusColor =
        stale || value == '—' || (!isSimulated && reportedStatus == null)
        ? ConsoleStyle.faint
        : highlight
        ? ConsoleStyle.warning
        : ConsoleStyle.good;
    final status = value == '—'
        ? 'Unavailable'
        : stale
        ? 'Last known'
        : !isSimulated
        ? reportedStatus ?? 'Status unknown'
        : attention
        ? 'Attention'
        : 'Normal';
    return Semantics(
      label:
          '$label $value $unit. $status. ${isSimulated ? 'Simulated' : 'ESP32 reported'} reading.',
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
                color: highlight && !stale
                    ? ConsoleStyle.warning
                    : Colors.transparent,
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
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          icon,
                          size: short ? 16 : 20,
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
                              fontSize: short ? 13 : 15,
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
                              fontSize: short ? 40 : 68,
                              fontWeight: FontWeight.w600,
                              letterSpacing: short ? -.8 : -1.5,
                              fontFeatures: ConsoleStyle.tabular,
                              color: stale
                                  ? ConsoleStyle.faint
                                  : highlight
                                  ? ConsoleStyle.warning
                                  : ConsoleStyle.text,
                            ),
                            TextSpan(
                              children: [
                                TextSpan(text: value),
                                if (unit.isNotEmpty)
                                  TextSpan(
                                    text: ' $unit',
                                    style: TextStyle(
                                      fontSize: short ? 15 : 20,
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
                              fontSize: short ? 12 : 14,
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

import 'package:flutter/material.dart';
import '../controllers/console_controller.dart';
import '../models/console_command.dart';
import 'console_command_sheet.dart';
import 'console_panel.dart';
import 'console_style.dart';

class ConsolePumpSheet extends StatelessWidget {
  const ConsolePumpSheet({
    super.key,
    required this.controller,
    required this.pumpA,
  });
  final ConsoleController controller;
  final bool pumpA;
  Future<void> _submit(
    BuildContext context,
    ConsoleAction action,
    String description,
  ) async {
    final approved =
        action.isStop ||
        await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: Text(
                  action.isRefill
                      ? 'Confirm physical refill?'
                      : action.isRetract
                      ? 'Retract full stroke?'
                      : 'Dispense configured dose?',
                ),
                content: Text(
                  controller.state?.isSimulated == true
                      ? 'Prototype · simulated data. No hardware action will occur.\n\n$description'
                      : description,
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Confirm'),
                  ),
                ],
              ),
            ) ==
            true;
    if (approved && context.mounted) await controller.submit(action);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final state = controller.state;
      final equipment = state?.equipment;
      final pump = pumpA ? equipment?.pumpA : equipment?.pumpB;
      final actuator = pumpA ? ConsoleActuator.pumpA : ConsoleActuator.pumpB;
      final command = state?.commands[actuator];
      final running = pump?.active == true;
      final reported = pump?.active == null
          ? 'Unknown'
          : running
          ? 'Running'
          : 'Idle';
      final stale = state?.readingsStale == true;
      final dispense = pumpA
          ? ConsoleAction.pumpADispense
          : ConsoleAction.pumpBDispense;
      final retract = pumpA
          ? ConsoleAction.pumpARetract
          : ConsoleAction.pumpBRetract;
      final refill = pumpA
          ? ConsoleAction.pumpARefill
          : ConsoleAction.pumpBRefill;
      final stop = pumpA ? ConsoleAction.pumpAStop : ConsoleAction.pumpBStop;
      final bothIdle =
          equipment?.pumpA.active == false && equipment?.pumpB.active == false;
      String ml(double? value) =>
          value == null ? 'Unavailable' : '${value.toStringAsFixed(2)} mL';
      final remaining = pump?.volumeKnown == true ? pump?.remainingMl : null;
      final capacity = pump?.capacityMl;
      Widget button(
        ConsoleAction action,
        String label,
        String confirmation,
        bool available, {
        required ButtonStyle style,
        IconData? icon,
      }) {
        final onPressed = available && controller.canSubmit(action)
            ? () => _submit(context, action, confirmation)
            : null;
        return SizedBox(
          height: 52,
          child: icon == null
              ? FilledButton(
                  onPressed: onPressed,
                  style: style,
                  child: Text(label),
                )
              : FilledButton.icon(
                  onPressed: onPressed,
                  style: style,
                  icon: Icon(icon, size: 20),
                  label: Text(label),
                ),
        );
      }

      return Padding(
        padding: const EdgeInsets.all(24),
        child: ConsoleStaggerColumn(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            ConsolePanelHeader(
              icon: Icons.science_outlined,
              title: pumpA ? 'Pump A' : 'Pump B',
              subtitle: state?.isSimulated == true
                  ? 'Prototype · simulated data'
                  : 'Firmware-controlled dosing and maintenance',
              closeTooltip: 'Close pump controls',
            ),
            const SizedBox(height: 20),
            if (state?.isSimulated == true) ...[
              const _Notice(
                'Demo only · no ESP32 or physical dispensing. 1 mL dose, '
                '5 mL syringe, shared 2-hour cooldown. Reset in settings.',
              ),
              const SizedBox(height: 14),
            ],
            ConsoleInset(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: running
                              ? ConsoleStyle.accent
                              : pump?.active == null
                              ? ConsoleStyle.warning
                              : ConsoleStyle.faint,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        reported,
                        style: const TextStyle(
                          fontSize: 30,
                          height: 1,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      if (stale)
                        const ConsoleTag(
                          label: 'Stale',
                          color: ConsoleStyle.warning,
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        'Syringe',
                        style: TextStyle(
                          fontSize: 13,
                          color: ConsoleStyle.muted,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        remaining == null
                            ? 'Unconfirmed / ${ml(capacity)}'
                            : '${ml(remaining)} / ${ml(capacity)}',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          fontFeatures: ConsoleStyle.tabular,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _Gauge(
                    fraction: remaining == null || capacity == null
                        ? null
                        : capacity <= 0
                        ? 0
                        : (remaining / capacity).clamp(0, 1).toDouble(),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      ConsoleFact('Dose', ml(pump?.volumeMl)),
                      ConsoleFact(
                        'Next eligible',
                        pump?.nextEligibleAt?.isNotEmpty == true
                            ? pump!.nextEligibleAt!
                            : 'Not reported',
                      ),
                      ConsoleFact(
                        'Clock',
                        pump?.clockSynced == true
                            ? 'Synced'
                            : pump?.clockSynced == false
                            ? 'Waiting'
                            : 'Unknown',
                        warn: pump?.clockSynced != true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // Device-reported history: covers schedules and other
                  // clients, not just commands sent from this console.
                  Row(
                    children: [
                      ConsoleFact('Doses', pump?.doseCount?.toString() ?? '—'),
                      ConsoleFact(
                        'Last dose',
                        pump?.lastDispensed ?? 'Not reported',
                      ),
                      ConsoleFact(
                        'Next scheduled',
                        pump?.nextDoseAt ?? 'Not reported',
                      ),
                    ],
                  ),
                  if (pump?.scheduleEvent != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      pump!.scheduleEvent!,
                      style: const TextStyle(
                        fontSize: 13,
                        color: ConsoleStyle.warning,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
            const ConsoleSectionLabel('Last command'),
            KeyedSubtree(
              key: const ValueKey('console-pump-command'),
              child: ConsoleCommandProgress(command: command),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: button(
                    dispense,
                    'Dispense ${ml(pump?.volumeMl)}',
                    'Check the syringe contents and tubing. Send one configured ${ml(pump?.volumeMl)} dose. Firmware cooldown, volume and mutual exclusion apply. An uncertain request will not be repeated automatically.',
                    bothIdle &&
                        pump?.validDose == true &&
                        pump?.volumeKnown == true &&
                        pump?.remainingMl != null &&
                        pump!.remainingMl! + .001 >= pump.volumeMl!,
                    style: _style(ConsoleStyle.accent, ConsoleStyle.background),
                    icon: Icons.water_drop_outlined,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: button(
                    stop,
                    'Stop motor',
                    '',
                    pump?.active != null,
                    // Stop is quiet at rest and turns solid red while running.
                    style: running
                        ? _style(ConsoleStyle.critical, ConsoleStyle.background)
                        : _style(
                            ConsoleStyle.critical.withValues(alpha: .14),
                            ConsoleStyle.critical,
                          ),
                    icon: Icons.stop_rounded,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const ConsoleSectionLabel('Maintenance'),
            Row(
              children: [
                Expanded(
                  child: button(
                    retract,
                    'Retract full stroke',
                    'This moves the motor through the firmware full-capacity reverse stroke. Check tubing and mechanics first. It does not confirm liquid volume or reset cooldown.',
                    bothIdle,
                    style: _style(ConsoleStyle.pressed, ConsoleStyle.text),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: button(
                    refill,
                    'Confirm refill',
                    'Only confirm after physically checking/refilling this syringe to ${ml(capacity)}. This changes the firmware volume estimate, moves no motor and does not reset cooldown.',
                    bothIdle &&
                        capacity != null &&
                        capacity > 0 &&
                        capacity <= 5,
                    style: _style(ConsoleStyle.pressed, ConsoleStyle.text),
                  ),
                ),
              ],
            ),
            if (state?.localConnected != true) ...[
              const SizedBox(height: 14),
              const Text(
                'Local device unavailable. Controls disabled.',
                style: TextStyle(color: ConsoleStyle.warning),
              ),
            ],
          ],
        ),
      );
    },
  );

  static ButtonStyle _style(Color background, Color foreground) =>
      FilledButton.styleFrom(
        backgroundColor: background,
        foregroundColor: foreground,
        disabledBackgroundColor: ConsoleStyle.surface,
        disabledForegroundColor: ConsoleStyle.faint,
        minimumSize: const Size(0, 52),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        textStyle: const TextStyle(
          fontFamily: 'Geist',
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      );
}

class _Notice extends StatelessWidget {
  const _Notice(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
    decoration: BoxDecoration(
      color: ConsoleStyle.warning.withValues(alpha: .10),
      borderRadius: BorderRadius.circular(ConsoleStyle.controlRadius),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline, size: 18, color: ConsoleStyle.warning),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: ConsoleStyle.warning.withValues(alpha: .9),
            ),
          ),
        ),
      ],
    ),
  );
}

/// Remaining syringe volume; an unconfirmed volume draws an empty track.
class _Gauge extends StatelessWidget {
  const _Gauge({required this.fraction});
  final double? fraction;
  @override
  Widget build(BuildContext context) => Container(
    height: 8,
    decoration: BoxDecoration(
      color: ConsoleStyle.pressed,
      borderRadius: BorderRadius.circular(4),
    ),
    alignment: Alignment.centerLeft,
    child: FractionallySizedBox(
      widthFactor: fraction ?? 0,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          color: (fraction ?? 0) < .25
              ? ConsoleStyle.warning
              : ConsoleStyle.accent,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    ),
  );
}

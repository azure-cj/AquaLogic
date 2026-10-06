import 'package:flutter/material.dart';
import '../controllers/console_controller.dart';
import '../models/console_command.dart';
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
                content: Text(description),
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
      final reported = pump?.active == null
          ? 'Unknown'
          : pump!.active!
          ? 'Running'
          : 'Idle';
      final status = state?.readingsStale == true
          ? 'Stale · $reported'
          : reported;
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
      Widget button(
        ConsoleAction action,
        String label,
        String confirmation,
        bool available,
      ) => SizedBox(
        height: 52,
        child: FilledButton(
          onPressed: available && controller.canSubmit(action)
              ? () => _submit(context, action, confirmation)
              : null,
          child: Text(label),
        ),
      );
      return Padding(
        padding: const EdgeInsets.all(24),
        child: ConsoleStaggerColumn(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            ConsolePanelHeader(
              icon: Icons.science_outlined,
              title: pumpA ? 'Pump A' : 'Pump B',
              subtitle: 'Firmware-controlled dosing and maintenance',
              closeTooltip: 'Close pump controls',
            ),
            const SizedBox(height: 20),
            ConsoleInset(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(status, style: const TextStyle(fontSize: 32)),
                  Text('Configured dose: ${ml(pump?.volumeMl)}'),
                  Text(
                    'Estimated remaining: ${pump?.volumeKnown == true ? ml(pump?.remainingMl) : 'Unconfirmed'} / ${ml(pump?.capacityMl)}',
                  ),
                  Text(
                    'Next eligible: ${pump?.nextEligibleAt?.isNotEmpty == true ? pump!.nextEligibleAt! : 'Not reported'}',
                  ),
                  Text(
                    'Clock: ${pump?.clockSynced == true
                        ? 'Synchronized'
                        : pump?.clockSynced == false
                        ? 'Waiting for sync'
                        : 'Unknown'}',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              command == null
                  ? 'No command submitted.'
                  : '${command.status.label} · ${command.message}',
              key: const ValueKey('console-pump-command'),
              style: TextStyle(
                color:
                    command?.status == ConsoleCommandStatus.unknown ||
                        command?.status == ConsoleCommandStatus.rejected
                    ? ConsoleStyle.warning
                    : ConsoleStyle.muted,
              ),
            ),
            const SizedBox(height: 16),
            button(
              dispense,
              'Dispense ${ml(pump?.volumeMl)}',
              'Check the syringe contents and tubing. Send one configured ${ml(pump?.volumeMl)} dose. Firmware cooldown, volume and mutual exclusion apply. An uncertain request will not be repeated automatically.',
              bothIdle &&
                  pump?.validDose == true &&
                  pump?.volumeKnown == true &&
                  pump?.remainingMl != null &&
                  pump!.remainingMl! + .001 >= pump.volumeMl!,
            ),
            const SizedBox(height: 10),
            button(stop, 'Stop motor', '', pump?.active != null),
            const SizedBox(height: 10),
            button(
              retract,
              'Retract full stroke',
              'This moves the motor through the firmware full-capacity reverse stroke. Check tubing and mechanics first. It does not confirm liquid volume or reset cooldown.',
              bothIdle,
            ),
            const SizedBox(height: 10),
            button(
              refill,
              'Confirm refill',
              'Only confirm after physically checking/refilling this syringe to ${ml(pump?.capacityMl)}. This changes the firmware volume estimate, moves no motor and does not reset cooldown.',
              bothIdle &&
                  pump?.capacityMl != null &&
                  pump!.capacityMl! > 0 &&
                  pump.capacityMl! <= 5,
            ),
            if (state?.localConnected != true) ...[
              const SizedBox(height: 12),
              const Text('Local device unavailable. Controls disabled.'),
            ],
          ],
        ),
      );
    },
  );
}

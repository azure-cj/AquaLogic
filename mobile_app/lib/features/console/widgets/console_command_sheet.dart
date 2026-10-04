import 'package:flutter/material.dart';
import '../controllers/console_controller.dart';
import '../models/console_command.dart';
import 'console_style.dart';

class ConsoleCommandSheet extends StatelessWidget {
  const ConsoleCommandSheet({
    super.key,
    required this.controller,
    required this.title,
    required this.action,
    this.readOnly = false,
  });
  final ConsoleController controller;
  final String title;
  final ConsoleAction? action;
  final bool readOnly;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final state = controller.state;
      final command = state?.command;
      final current = switch (action) {
        ConsoleAction.lightOn || ConsoleAction.lightOff =>
          state?.equipment.lightConfirmed != true
              ? 'UNKNOWN'
              : state?.equipment.lightOn == true
              ? 'ON'
              : 'OFF',
        ConsoleAction.uvOn || ConsoleAction.uvOff =>
          state?.equipment.uvConfirmed != true
              ? 'UNKNOWN'
              : state?.equipment.uvOn == true
              ? 'ON'
              : 'OFF',
        _ =>
          state?.equipment.feederConfirmed != true
              ? 'UNKNOWN'
              : state?.equipment.feederRunning == true
              ? 'RUNNING'
              : 'READY',
      };
      // Resolve the target at submission time; a reopened sheet uses current state.
      final actualAction = switch (action) {
        ConsoleAction.lightOn || ConsoleAction.lightOff =>
          state?.equipment.lightOn == true
              ? ConsoleAction.lightOff
              : ConsoleAction.lightOn,
        ConsoleAction.uvOn || ConsoleAction.uvOff =>
          state?.equipment.uvOn == true
              ? ConsoleAction.uvOff
              : ConsoleAction.uvOn,
        _ => action,
      };
      final text = actualAction == ConsoleAction.feed
          ? 'FEED ONCE'
          : actualAction == ConsoleAction.lightOff ||
                actualAction == ConsoleAction.uvOff
          ? 'TURN OFF'
          : 'TURN ON';
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close controls',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const Text(
              'Prototype · simulated data',
              style: TextStyle(color: ConsoleStyle.accent),
            ),
            const SizedBox(height: 16),
            if (readOnly)
              const Text(
                'IDLE · READ ONLY\nDosing controls will be available in a later phase after local device integration and safety review.',
                style: TextStyle(fontSize: 17, height: 1.5),
              )
            else ...[
              Text(
                'Current status: $current',
                style: const TextStyle(fontSize: 20),
              ),
              const SizedBox(height: 12),
              Text(
                command == null
                    ? 'IDLE · No command submitted.'
                    : '${command.status.label} · ${command.message}',
                key: const ValueKey('console-sheet-command'),
                style: TextStyle(
                  fontSize: 15,
                  color:
                      command?.status == ConsoleCommandStatus.unknown ||
                          command?.status == ConsoleCommandStatus.rejected
                      ? ConsoleStyle.warning
                      : ConsoleStyle.muted,
                ),
              ),
              if (controller.error != null)
                Text(
                  controller.error!,
                  style: const TextStyle(color: ConsoleStyle.warning),
                ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed:
                    controller.canCommand &&
                        actualAction != null &&
                        current != 'UNKNOWN'
                    ? () => controller.submit(actualAction)
                    : null,
                child: Text(
                  controller.busy
                      ? 'COMMAND IN PROGRESS'
                      : state?.localConnected != true
                      ? 'LOCAL DEVICE OFFLINE'
                      : current == 'UNKNOWN'
                      ? 'EQUIPMENT STATE UNCONFIRMED'
                      : text,
                ),
              ),
            ],
          ],
        ),
      );
    },
  );
}

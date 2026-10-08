import 'package:flutter/material.dart';
import '../controllers/console_controller.dart';
import '../models/console_command.dart';
import 'console_panel.dart';
import 'console_style.dart';

class ConsoleCommandSheet extends StatelessWidget {
  const ConsoleCommandSheet({
    super.key,
    required this.controller,
    required this.title,
    required this.action,
    this.icon = Icons.tune_rounded,
    this.readOnly = false,
  });
  final ConsoleController controller;
  final String title;
  final ConsoleAction? action;
  final IconData icon;
  final bool readOnly;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final state = controller.state;
      final pumpStatus = title == 'Pump A'
          ? state?.equipment.pumpAStatus
          : state?.equipment.pumpBStatus;
      final command =
          state?.commands[action?.actuator] ??
          (state?.command?.action.actuator == action?.actuator
              ? state?.command
              : null);
      final current = switch (action) {
        ConsoleAction.lightOn || ConsoleAction.lightOff =>
          state?.equipment.lightConfirmed != true
              ? 'Unknown'
              : state?.equipment.lightOn == true
              ? 'On'
              : 'Off',
        ConsoleAction.uvOn || ConsoleAction.uvOff =>
          state?.equipment.uvConfirmed != true
              ? 'Unknown'
              : state?.equipment.uvOn == true
              ? 'On'
              : 'Off',
        _ =>
          state?.equipment.feederConfirmed != true
              ? 'Unknown'
              : state?.equipment.feederRunning == true
              ? 'Running'
              : 'Ready',
      };
      final active = current == 'On' || current == 'Running';
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
          ? 'Feed once'
          : actualAction == ConsoleAction.lightOff ||
                actualAction == ConsoleAction.uvOff
          ? 'Turn off'
          : 'Turn on';
      final enabled =
          actualAction != null &&
          controller.canSubmit(actualAction) &&
          current != 'Unknown' &&
          (actualAction != ConsoleAction.feed || current != 'Running');
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
        child: ConsoleStaggerColumn(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ConsolePanelHeader(
              icon: icon,
              title: title,
              subtitle: readOnly
                  ? 'Monitoring only'
                  : state?.isSimulated == true
                  ? 'Prototype · simulated data'
                  : 'Local control',
              closeTooltip: 'Close controls',
            ),
            const SizedBox(height: 28),
            if (readOnly) ...[
              const ConsoleSectionLabel('Status'),
              ConsoleInset(
                child: Row(
                  children: [
                    Text(
                      pumpStatus ?? 'Unknown',
                      style: const TextStyle(
                        fontSize: 32,
                        height: 1,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    _Tag(
                      icon: Icons.lock_outline,
                      label: 'Read only',
                      color: ConsoleStyle.muted,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Pump control is unavailable for this connection. Status remains read-only.',
                style: TextStyle(color: ConsoleStyle.muted, height: 1.5),
              ),
            ] else ...[
              const ConsoleSectionLabel('Current state'),
              ConsoleInset(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: active
                            ? ConsoleStyle.accent
                            : current == 'Unknown'
                            ? ConsoleStyle.warning
                            : ConsoleStyle.faint,
                        boxShadow: active
                            ? [
                                BoxShadow(
                                  color: ConsoleStyle.accent.withValues(
                                    alpha: .5,
                                  ),
                                  blurRadius: 10,
                                ),
                              ]
                            : null,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Text(
                      current,
                      key: const ValueKey('console-sheet-current'),
                      style: const TextStyle(
                        fontSize: 32,
                        height: 1,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    if (state?.isSimulated == true)
                      const _Tag(
                        label: 'Simulated',
                        color: ConsoleStyle.warning,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const ConsoleSectionLabel('Last command'),
              _CommandProgress(command: command),
              if (controller.error != null) ...[
                const SizedBox(height: 10),
                Text(
                  controller.error!,
                  style: const TextStyle(color: ConsoleStyle.warning),
                ),
              ],
              const SizedBox(height: 28),
              SizedBox(
                height: 56,
                child: FilledButton(
                  onPressed: enabled
                      ? () async {
                          if (actualAction == ConsoleAction.feed) {
                            final approved = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Feed once?'),
                                content: Text(
                                  state?.isSimulated == true
                                      ? 'Prototype · simulated data. Preview one feed cycle without hardware. An uncertain request will not be repeated automatically.'
                                      : 'Run one configured feed cycle. An uncertain request will not be repeated automatically.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, false),
                                    child: const Text('Cancel'),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.pop(context, true),
                                    child: const Text('Feed once'),
                                  ),
                                ],
                              ),
                            );
                            if (approved != true || !context.mounted) return;
                          }
                          await controller.submit(actualAction);
                        }
                      : null,
                  style: FilledButton.styleFrom(
                    disabledBackgroundColor: ConsoleStyle.surface,
                    disabledForegroundColor: ConsoleStyle.faint,
                  ),
                  child: Text(
                    command?.status.isPending == true
                        ? 'Command in progress'
                        : state?.localConnected != true
                        ? 'Local device offline'
                        : current == 'Unknown'
                        ? 'Equipment state unconfirmed'
                        : text,
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    },
  );
}

/// Live and simulated command stages, with failure states shown in amber.
class _CommandProgress extends StatelessWidget {
  const _CommandProgress({required this.command});
  final ConsoleCommand? command;

  @override
  Widget build(BuildContext context) {
    final command = this.command;
    if (command == null) {
      return const ConsoleInset(
        child: Text(
          'No command submitted.',
          key: ValueKey('console-sheet-command'),
          style: TextStyle(color: ConsoleStyle.muted),
        ),
      );
    }
    final failed =
        command.status == ConsoleCommandStatus.rejected ||
        command.status == ConsoleCommandStatus.failed ||
        command.status == ConsoleCommandStatus.unknown;
    final reached = switch (command.status) {
      ConsoleCommandStatus.idle => 0,
      ConsoleCommandStatus.accepted => 1,
      ConsoleCommandStatus.running => 2,
      ConsoleCommandStatus.completed => 3,
      ConsoleCommandStatus.sending => 1,
      ConsoleCommandStatus.confirming => 2,
      ConsoleCommandStatus.confirmed => 3,
      _ => 0,
    };
    final live = switch (command.status) {
      ConsoleCommandStatus.accepted ||
      ConsoleCommandStatus.running ||
      ConsoleCommandStatus.completed => false,
      _ => true,
    };
    final steps = live
        ? ['Sending', 'Confirming', 'Confirmed']
        : ['Accepted', 'Running', 'Completed'];
    return ConsoleInset(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!failed)
            Wrap(
              spacing: 16,
              runSpacing: 10,
              children: [
                for (var i = 0; i < steps.length; i++)
                  _Step(label: steps[i], done: i < reached),
              ],
            ),
          if (!failed) const SizedBox(height: 14),
          Text(
            '${command.status.label} · ${command.message}',
            key: const ValueKey('console-sheet-command'),
            style: TextStyle(
              fontSize: 14,
              color: failed ? ConsoleStyle.warning : ConsoleStyle.muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.label, required this.done});
  final String label;
  final bool done;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: done ? ConsoleStyle.accent : Colors.transparent,
          border: Border.all(
            color: done ? ConsoleStyle.accent : ConsoleStyle.faint,
            width: 1.5,
          ),
        ),
        child: done
            ? const Icon(
                Icons.check_rounded,
                size: 12,
                color: ConsoleStyle.background,
              )
            : null,
      ),
      const SizedBox(width: 6),
      Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: done ? ConsoleStyle.text : ConsoleStyle.faint,
        ),
      ),
    ],
  );
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.color, this.icon});
  final String label;
  final Color color;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
        ],
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            height: 1,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    ),
  );
}

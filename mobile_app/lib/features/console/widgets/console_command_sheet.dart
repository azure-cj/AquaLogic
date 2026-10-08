import 'package:flutter/material.dart';
import '../controllers/console_controller.dart';
import '../models/console_command.dart';
import '../models/console_state.dart';
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
      final enabled =
          actualAction != null &&
          controller.canSubmit(actualAction) &&
          current != 'Unknown' &&
          (actualAction != ConsoleAction.feed || current != 'Running');
      // Says why the control is unavailable instead of a silent grey button.
      final blocked = enabled
          ? null
          : command?.status.isPending == true
          ? 'Command in progress. Waiting for the device to confirm.'
          : state?.localConnected != true
          ? 'Local device offline. Controls are disabled.'
          : current == 'Unknown'
          ? 'Equipment state unconfirmed. No command will be sent.'
          : current == 'Running'
          ? 'Feeding now.'
          : 'Controls unavailable right now.';
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
                    ConsoleTag(
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
                      const ConsoleTag(
                        label: 'Simulated',
                        color: ConsoleStyle.warning,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ..._control(
                blocked: blocked,
                enabled: enabled,
                active: active,
                current: current,
              ),
              const SizedBox(height: 24),
              const ConsoleSectionLabel('Last command'),
              ConsoleCommandProgress(command: command),
              if (controller.error != null) ...[
                const SizedBox(height: 10),
                Text(
                  controller.error!,
                  style: const TextStyle(color: ConsoleStyle.warning),
                ),
              ],
              if (action == ConsoleAction.feed) ...[
                const SizedBox(height: 24),
                const ConsoleSectionLabel('Device reports'),
                _FeederDetails(equipment: state?.equipment),
              ],
            ],
          ],
        ),
      );
    },
  );

  /// The panel's one control, directly under the current state.
  List<Widget> _control({
    required String? blocked,
    required bool enabled,
    required bool active,
    required String current,
  }) => [
    if (blocked != null) ...[
      Text(
        blocked,
        key: const ValueKey('console-sheet-blocked'),
        style: const TextStyle(fontSize: 14, color: ConsoleStyle.muted),
      ),
      const SizedBox(height: 10),
    ],
    if (action == ConsoleAction.feed)
      ConsoleHoldButton(
        key: const ValueKey('console-feed-hold'),
        label: 'Hold to feed',
        icon: Icons.set_meal_outlined,
        onHold: enabled ? () => controller.submit(ConsoleAction.feed) : null,
      )
    else
      _OnOffSwitch(
        on: current == 'Unknown' ? null : active,
        onChanged: enabled
            ? (value) => controller.submit(
                action == ConsoleAction.lightOn ||
                        action == ConsoleAction.lightOff
                    ? (value ? ConsoleAction.lightOn : ConsoleAction.lightOff)
                    : (value ? ConsoleAction.uvOn : ConsoleAction.uvOff),
              )
            : null,
      ),
  ];
}

/// Two large segments; the device-confirmed side is lit. Tapping the other
/// side sends one command, and the highlight only moves once confirmed.
class _OnOffSwitch extends StatelessWidget {
  const _OnOffSwitch({required this.on, required this.onChanged});
  final bool? on;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => Container(
    height: 64,
    padding: const EdgeInsets.all(5),
    decoration: BoxDecoration(
      color: ConsoleStyle.background.withValues(alpha: .55),
      borderRadius: BorderRadius.circular(ConsoleStyle.controlRadius + 4),
      border: Border.all(color: ConsoleStyle.hairline),
    ),
    child: Row(
      children: [
        for (final value in [false, true])
          Expanded(
            child: Semantics(
              button: true,
              selected: on == value,
              child: GestureDetector(
                key: ValueKey('console-switch-${value ? 'on' : 'off'}'),
                onTap: onChanged == null || on == value
                    ? null
                    : () => onChanged!(value),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: on == value
                        ? (value ? ConsoleStyle.accent : ConsoleStyle.pressed)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(
                      ConsoleStyle.controlRadius,
                    ),
                  ),
                  child: Text(
                    value ? 'On' : 'Off',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: on == value
                          ? (value
                                ? ConsoleStyle.background
                                : ConsoleStyle.text)
                          : onChanged == null
                          ? ConsoleStyle.faint
                          : ConsoleStyle.muted,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

/// Read-only feeder facts from /feeder/status. Portion and schedule are
/// edited in the web app, not on the wall-mounted console.
class _FeederDetails extends StatelessWidget {
  const _FeederDetails({required this.equipment});
  final ConsoleEquipmentState? equipment;

  static String _time(ConsoleScheduleSlot slot) {
    final hour = slot.hour % 12 == 0 ? 12 : slot.hour % 12;
    final minute = slot.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${slot.hour < 12 ? 'AM' : 'PM'}';
  }

  @override
  Widget build(BuildContext context) {
    final equipment = this.equipment;
    final angle = equipment?.feederAngle;
    final duration = equipment?.feederDurationMs;
    final schedule = equipment?.feederSchedule ?? const [];
    return ConsoleInset(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ConsoleFact('Feeds', equipment?.feedCount?.toString() ?? '—'),
              ConsoleFact('Last fed', equipment?.lastFed ?? 'Not reported'),
              ConsoleFact(
                'Portion',
                angle == null || duration == null
                    ? 'Not reported'
                    : '$angle° · ${(duration / 1000).toStringAsFixed(1)} s',
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Schedule',
            style: TextStyle(fontSize: 12, color: ConsoleStyle.faint),
          ),
          const SizedBox(height: 8),
          if (schedule.isEmpty)
            const Text('Not reported', style: TextStyle(fontSize: 15))
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final slot in schedule)
                  ConsoleTag(
                    label: slot.enabled ? _time(slot) : '${_time(slot)} · off',
                    color: slot.enabled
                        ? ConsoleStyle.accent
                        : ConsoleStyle.faint,
                  ),
              ],
            ),
          const SizedBox(height: 14),
          const Text(
            'Edit portion and schedule in the AquaLogic web app.',
            style: TextStyle(fontSize: 13, color: ConsoleStyle.muted),
          ),
        ],
      ),
    );
  }
}

/// Live and simulated command stages, with failure states shown in amber.
class ConsoleCommandProgress extends StatelessWidget {
  const ConsoleCommandProgress({super.key, required this.command});
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

class ConsoleTag extends StatelessWidget {
  const ConsoleTag({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });
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

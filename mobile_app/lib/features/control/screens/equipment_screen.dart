import 'package:aqualogic/app/theme/app_colors.dart';
import 'package:aqualogic/features/auth/models/auth_user.dart';
import 'package:aqualogic/features/auth/models/user_role.dart';
import 'package:aqualogic/features/control/data/mock_equipment_repository.dart';
import 'package:aqualogic/features/control/models/equipment_models.dart';
import 'package:aqualogic/features/tanks/models/tank_info.dart';
import 'package:aqualogic/shared/models/aqualogic_status.dart';
import 'package:aqualogic/shared/widgets/app_page.dart';
import 'package:aqualogic/shared/widgets/header_panel.dart';
import 'package:aqualogic/shared/widgets/semantic_status_widgets.dart';
import 'package:aqualogic/shared/widgets/soft_card.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class EquipmentScreen extends StatefulWidget {
  const EquipmentScreen({
    super.key,
    required this.tank,
    this.user,
    this.repository,
  });

  final TankInfo tank;
  final AuthUser? user;
  final EquipmentRepository? repository;

  @override
  State<EquipmentScreen> createState() => _EquipmentScreenState();
}

class _EquipmentScreenState extends State<EquipmentScreen> {
  late final EquipmentRepository _repository =
      widget.repository ?? const MockEquipmentRepository();
  late List<EquipmentDevice> _devices;
  late List<CommandRecord> _history;
  String? _latestLocalCommandId;

  bool get _canManage =>
      !widget.tank.isRetired &&
      (widget.user == null || widget.user!.role == UserRole.admin);

  @override
  void initState() {
    super.initState();
    final overview = _repository.load(tankId: widget.tank.tankId);
    _devices = overview.devices.toList();
    _history = overview.commandHistory.toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        top: false,
        child: AppPage(
          header: HeaderPanel(
            compact: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconButton.filledTonal(
                  tooltip: 'Back to ${widget.tank.name}',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(LucideIcons.arrowLeft),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Equipment',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  widget.tank.name,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          children: [
            if (!_canManage) _ReadOnlyNotice(isRetired: widget.tank.isRetired),
            const SectionHeader(
              title: 'Connected equipment',
              subtitle: 'Device connectivity is separate from tank status',
            ),
            if (_latestLocalCommandId case final commandId?)
              if (_findCommand(commandId) case final command?)
                _LatestCommandCard(command: command),
            for (final device in _devices)
              _EquipmentDeviceCard(
                device: device,
                canManage: _canManage,
                onAction: () => _requestCommand(device),
              ),
            const SectionHeader(
              title: 'Command history',
              subtitle: 'A record of local mock commands',
            ),
            if (_history.any(
              (command) => command.status == CommandStatus.outcomeUnknown,
            ))
              const _UnknownCommandNotice(),
            _CommandHistoryCard(history: _history),
          ],
        ),
      ),
    );
  }

  Future<void> _requestCommand(EquipmentDevice device) async {
    if (!_canManage) return;
    final isToggle =
        device.kind == EquipmentKind.uv || device.kind == EquipmentKind.led;
    final nextOn = device.powerState != EquipmentPowerState.on;
    final actionLabel = isToggle
        ? nextOn
              ? 'Turn on'
              : 'Turn off'
        : device.kind == EquipmentKind.feeder
        ? 'Feed now'
        : 'Run manual test';
    final powerVerb = nextOn ? 'on' : 'off';
    final title = isToggle
        ? 'Turn ${device.name} $powerVerb?'
        : device.isPump
        ? 'Run ${device.name}?'
        : '$actionLabel ${device.name}?';
    final message = device.isPump
        ? 'This is a physical water-control action. Verify the tank and equipment before continuing.'
        : 'This starts a deterministic local mock command for this prototype.';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    _beginCommand(device, actionLabel);
  }

  void _beginCommand(EquipmentDevice device, String actionLabel) {
    final id = 'local-command-${_history.length + 1}';
    final command = CommandRecord(
      id: id,
      equipmentId: device.id,
      equipmentName: device.name,
      actionLabel: actionLabel,
      status: CommandStatus.queued,
      timeLabel: 'Just now',
    );
    setState(() {
      _latestLocalCommandId = id;
      _history = [command, ..._history];
    });
    Future<void>.delayed(const Duration(milliseconds: 180), () {
      _setCommandStatus(id, CommandStatus.executing);
    });
    Future<void>.delayed(const Duration(milliseconds: 520), () {
      _setCommandStatus(id, CommandStatus.succeeded);
      _updateDeviceAfterCommand(device, actionLabel);
    });
  }

  CommandRecord? _findCommand(String id) {
    for (final command in _history) {
      if (command.id == id) return command;
    }
    return null;
  }

  void _setCommandStatus(String id, CommandStatus status) {
    if (!mounted) return;
    setState(() {
      _history = [
        for (final command in _history)
          command.id == id ? command.copyWith(status: status) : command,
      ];
    });
  }

  void _updateDeviceAfterCommand(EquipmentDevice device, String actionLabel) {
    if (!mounted) return;
    final index = _devices.indexWhere((item) => item.id == device.id);
    if (index < 0) return;
    final isToggle =
        device.kind == EquipmentKind.uv || device.kind == EquipmentKind.led;
    final state = isToggle
        ? actionLabel == 'Turn on'
              ? EquipmentPowerState.on
              : EquipmentPowerState.off
        : device.isPump
        ? EquipmentPowerState.idle
        : EquipmentPowerState.ready;
    setState(() {
      _devices[index] = device.copyWith(
        powerState: state,
        lastActionLabel: '$actionLabel completed just now',
      );
    });
  }
}

class _ReadOnlyNotice extends StatelessWidget {
  const _ReadOnlyNotice({required this.isRetired});

  final bool isRetired;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(LucideIcons.eye, color: AppColors.tealDark),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isRetired
                  ? 'This tank is retired. Equipment is shown for context and cannot be changed.'
                  : 'Staff access is read-only. Equipment commands are available to Owners only.',
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 12,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UnknownCommandNotice extends StatelessWidget {
  const _UnknownCommandNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.offline.withValues(alpha: 0.08),
        border: Border.all(color: AppColors.offline.withValues(alpha: 0.55)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            LucideIcons.circleHelp,
            color: AppColors.offline,
            size: 21,
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'The command may have physically executed, but confirmation was not received. Check the equipment before trying again.',
              style: TextStyle(
                color: AppColors.text,
                fontSize: 11,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LatestCommandCard extends StatelessWidget {
  const _LatestCommandCard({required this.command});

  final CommandRecord command;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      child: Row(
        children: [
          const Icon(LucideIcons.activity, color: AppColors.tealDark, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Latest command',
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  command.actionLabel,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          CommandStatusBadge(status: command.status),
        ],
      ),
    );
  }
}

class _EquipmentDeviceCard extends StatelessWidget {
  const _EquipmentDeviceCard({
    required this.device,
    required this.canManage,
    required this.onAction,
  });

  final EquipmentDevice device;
  final bool canManage;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final actionLabel =
        device.kind == EquipmentKind.uv || device.kind == EquipmentKind.led
        ? device.powerState == EquipmentPowerState.on
              ? 'Turn off'
              : 'Turn on'
        : device.kind == EquipmentKind.feeder
        ? 'Feed now'
        : 'Run now';
    final icon = switch (device.kind) {
      EquipmentKind.uv => LucideIcons.shieldCheck,
      EquipmentKind.led => LucideIcons.lightbulb,
      EquipmentKind.feeder => LucideIcons.utensils,
      EquipmentKind.pumpA || EquipmentKind.pumpB => LucideIcons.droplets,
    };

    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 21,
                backgroundColor: AppColors.teal.withValues(alpha: 0.17),
                child: Icon(icon, color: AppColors.tealDark, size: 20),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.name,
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      device.subtitle,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 11,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              DeviceConnectionBadge(status: device.connection, compact: true),
            ],
          ),
          const SizedBox(height: 13),
          Row(
            children: [
              Expanded(
                child: _DeviceInfo(
                  label: 'Current state',
                  value: device.stateLabel,
                ),
              ),
              Expanded(
                child: _DeviceInfo(
                  label: 'Schedule',
                  value: device.scheduleLabel,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            'Last command: ${device.lastActionLabel}',
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (canManage) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: device.connection == DeviceConnectionStatus.offline
                    ? null
                    : onAction,
                icon: Icon(
                  device.isPump ? LucideIcons.play : LucideIcons.power,
                  size: 16,
                ),
                label: Text(
                  device.connection == DeviceConnectionStatus.offline
                      ? 'Unavailable while offline'
                      : actionLabel,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DeviceInfo extends StatelessWidget {
  const _DeviceInfo({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.muted,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.text,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _CommandHistoryCard extends StatelessWidget {
  const _CommandHistoryCard({required this.history});

  final List<CommandRecord> history;

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty) {
      return const EmptyState(
        title: 'No command history',
        message: 'Commands issued for this tank will appear here.',
        icon: LucideIcons.history,
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
        boxShadow: [
          BoxShadow(
            color: AppColors.tealDark.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          initiallyExpanded: true,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          title: const Text(
            'Recent commands',
            style: TextStyle(
              color: AppColors.text,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          subtitle: Text(
            '${history.length} recorded command${history.length == 1 ? '' : 's'}',
            style: const TextStyle(color: AppColors.muted, fontSize: 11),
          ),
          leading: const Icon(LucideIcons.history, color: AppColors.tealDark),
          children: [
            for (var index = 0; index < history.length; index++) ...[
              _CommandRow(command: history[index]),
              if (index < history.length - 1)
                const Divider(height: 1, indent: 14, endIndent: 14),
            ],
          ],
        ),
      ),
    );
  }
}

class _CommandRow extends StatelessWidget {
  const _CommandRow({required this.command});

  final CommandRecord command;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  command.actionLabel,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${command.equipmentName} · ${command.timeLabel}',
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          CommandStatusBadge(status: command.status, compact: true),
        ],
      ),
    );
  }
}

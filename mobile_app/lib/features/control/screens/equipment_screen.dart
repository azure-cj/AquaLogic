import 'dart:async';

import 'package:aqualogic/app/theme/app_colors.dart';
import 'package:aqualogic/features/auth/models/auth_user.dart';
import 'package:aqualogic/features/auth/models/user_role.dart';
import 'package:aqualogic/features/control/data/mock_equipment_repository.dart';
import 'package:aqualogic/features/control/models/equipment_models.dart';
import 'package:aqualogic/features/tanks/models/tank_info.dart';
import 'package:aqualogic/shared/models/aqualogic_status.dart';
import 'package:aqualogic/shared/formatters/local_timestamps.dart';
import 'package:aqualogic/shared/network/api_failure.dart';
import 'package:aqualogic/shared/widgets/app_page.dart';
import 'package:aqualogic/features/more/widgets/more_header.dart';
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

class _EquipmentScreenState extends State<EquipmentScreen>
    with WidgetsBindingObserver {
  static const _foregroundRefreshInterval = Duration(minutes: 1);

  EquipmentRepository get _repository =>
      widget.repository ??
      (widget.tank.isLiveData
          ? const UnavailableEquipmentRepository()
          : const MockEquipmentRepository());

  List<RegisteredEquipmentDevice>? _registeredDevices;
  RegisteredEquipmentDevice? _selectedDevice;
  EquipmentOverview? _overview;
  ApiFailure? _initialFailure;
  ApiFailure? _refreshFailure;
  bool _loading = true;
  bool _backendRestricted = false;
  DateTime? _lastSuccessfulLoadAt;
  Future<void>? _loadInFlight;
  String? _latestLocalCommandId;

  bool get _canManage =>
      _repository.supportsCommandSimulation &&
      !_repository.isLiveData &&
      !widget.tank.isRetired &&
      (widget.user == null || widget.user!.role == UserRole.admin);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final lastSuccess = _lastSuccessfulLoadAt;
    if (_registeredDevices == null ||
        lastSuccess == null ||
        DateTime.now().toUtc().difference(lastSuccess) >=
            _foregroundRefreshInterval) {
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _load() {
    final inFlight = _loadInFlight;
    if (inFlight != null) return inFlight;
    final request = _loadEquipment();
    _loadInFlight = request;
    return request.whenComplete(() {
      if (identical(_loadInFlight, request)) _loadInFlight = null;
    });
  }

  Future<void> _loadEquipment() async {
    if (_repository.isLiveData &&
        (widget.user == null || widget.user!.role != UserRole.admin)) {
      if (mounted) {
        setState(() {
          _backendRestricted = true;
          _loading = false;
          _registeredDevices = const [];
          _overview = null;
        });
      }
      return;
    }
    if (mounted) {
      setState(() {
        _loading = true;
        _initialFailure = null;
      });
    }
    try {
      final devices = await _repository.listDevices(tankId: widget.tank.tankId);
      final previousId = _selectedDevice?.id;
      RegisteredEquipmentDevice? selected;
      for (final device in devices) {
        if (device.id == previousId) {
          selected = device;
          break;
        }
      }
      if (selected == null && devices.length == 1) selected = devices.single;
      if (!mounted) return;
      setState(() {
        _registeredDevices = devices;
        _selectedDevice = selected;
        _overview = null;
        _refreshFailure = null;
        _backendRestricted = false;
      });
      if (selected != null) {
        await _loadSelected(selected, firstLoad: true);
      }
      if (mounted) {
        setState(() {
          _initialFailure = null;
          _lastSuccessfulLoadAt = DateTime.now().toUtc();
        });
      }
    } catch (error) {
      if (!mounted) return;
      final failure = _asFailure(
        error,
        'Equipment devices could not be loaded.',
      );
      setState(() {
        if (failure.kind == ApiFailureKind.forbidden) {
          _backendRestricted = true;
          _registeredDevices = const [];
          _overview = null;
        } else if (_registeredDevices == null) {
          _initialFailure = failure;
        } else {
          _refreshFailure = failure;
        }
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _selectDevice(RegisteredEquipmentDevice device) async {
    setState(() {
      _selectedDevice = device;
      _overview = null;
      _initialFailure = null;
      _refreshFailure = null;
      _loading = true;
    });
    await _loadSelected(device, firstLoad: true);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadSelected(
    RegisteredEquipmentDevice device, {
    required bool firstLoad,
  }) async {
    try {
      final result = await _repository.load(
        tankId: widget.tank.tankId,
        device: device,
      );
      if (!mounted) return;
      setState(() {
        _overview = result;
        _initialFailure = null;
        _refreshFailure = null;
        _backendRestricted =
            result.statusFailure?.kind == ApiFailureKind.forbidden &&
            result.historyFailure?.kind == ApiFailureKind.forbidden;
        if (result.statusFailure == null || result.historyFailure == null) {
          _lastSuccessfulLoadAt = DateTime.now().toUtc();
        }
      });
    } catch (error) {
      if (!mounted) return;
      final failure = _asFailure(error, 'Equipment state could not be loaded.');
      setState(() {
        if (failure.kind == ApiFailureKind.forbidden) {
          _backendRestricted = true;
        } else if (firstLoad && _overview == null) {
          _initialFailure = failure;
        } else {
          _refreshFailure = failure;
        }
      });
    }
  }

  ApiFailure _asFailure(Object error, String fallback) => error is ApiFailure
      ? error
      : ApiFailure(
          kind: ApiFailureKind.unknown,
          message: '$fallback Try again.',
          retryable: true,
        );

  @override
  Widget build(BuildContext context) {
    final devices = _registeredDevices;
    final selectedDevice = _selectedDevice;
    final overview = _overview;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        top: false,
        child: AppPage(
          onRefresh: _load,
          header: MoreHeader(
            title: 'Equipment',
            subtitle: widget.tank.name,
            backLabel: 'Back to ${widget.tank.name}',
            onBack: () => Navigator.of(context).pop(),
          ),
          children: [
            if (_backendRestricted)
              _ReadOnlyNotice(
                isRetired: widget.tank.isRetired,
                isBackendRestricted: true,
              )
            else if (devices == null)
              _loading
                  ? const _EquipmentLoadingState()
                  : _EquipmentErrorState(
                      message:
                          _initialFailure?.message ??
                          'Check your connection and retry.',
                      retrying: _loading,
                      onRetry: () => unawaited(_load()),
                    )
            else if (devices.isEmpty)
              const EmptyState(
                title: 'No registered equipment device',
                message:
                    'AquaLogic has no registered bridge device for this tank.',
                icon: LucideIcons.router,
              )
            else ...[
              if (_refreshFailure != null)
                _EquipmentStaleState(
                  message: _refreshFailure!.message,
                  onRetry: () => unawaited(_load()),
                ),
              if (!_repository.isLiveData && !_canManage)
                _ReadOnlyNotice(isRetired: widget.tank.isRetired),
              if (devices.length > 1)
                _EquipmentDeviceSelector(
                  devices: devices,
                  selected: selectedDevice,
                  onChanged: (device) {
                    if (device != null) unawaited(_selectDevice(device));
                  },
                ),
              if (devices.length > 1 && selectedDevice == null)
                const EmptyState(
                  title: 'Select a registered device',
                  message:
                      'More than one device is attached to this tank. Choose which device state and history to view.',
                  icon: LucideIcons.router,
                )
              else if (selectedDevice != null && overview == null)
                _loading
                    ? const _EquipmentLoadingState()
                    : _EquipmentErrorState(
                        message:
                            _initialFailure?.message ??
                            'Equipment state could not be loaded.',
                        retrying: _loading,
                        onRetry: () => unawaited(_load()),
                      )
              else if (selectedDevice != null && overview != null) ...[
                if (_repository.isLiveData) const _EquipmentReadOnlyBanner(),
                if (_latestLocalCommandId case final commandId?)
                  if (_findCommand(commandId) case final command?)
                    _LatestCommandCard(command: command),
                const SectionHeader(
                  title: 'Connected equipment',
                  subtitle: 'Device connectivity is separate from tank status',
                ),
                if (overview.statusFailure != null)
                  _EquipmentSourceState(
                    title: 'Equipment state unavailable',
                    message: overview.statusFailure!.message,
                    onRetry: () => unawaited(_load()),
                  )
                else if (overview.devices.isEmpty)
                  const EmptyState(
                    title: 'No actuator state yet',
                    message:
                        'The selected device has not reported actuator state.',
                    icon: LucideIcons.circleHelp,
                  )
                else
                  for (final device in overview.devices)
                    _EquipmentDeviceCard(
                      device: device,
                      canManage: _canManage,
                      onAction: () => _requestCommand(device),
                    ),
                const SectionHeader(
                  title: 'Command history',
                  subtitle:
                      'Backend command lifecycle records; success is not physical verification',
                ),
                if (overview.historyFailure != null)
                  _EquipmentSourceState(
                    title: 'Command history unavailable',
                    message: overview.historyFailure!.message,
                    onRetry: () => unawaited(_load()),
                  )
                else ...[
                  if (overview.commandHistory.any(
                    (command) => command.status == CommandStatus.outcomeUnknown,
                  ))
                    const _UnknownCommandNotice(),
                  _CommandHistoryCard(history: overview.commandHistory),
                ],
              ],
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _requestCommand(EquipmentDevice device) async {
    if (!_canManage ||
        _repository.isLiveData ||
        device.kind == EquipmentKind.unknown) {
      return;
    }
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
    final history = _overview?.commandHistory ?? const <CommandRecord>[];
    final id = 'local-command-${history.length + 1}';
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
      _overview = EquipmentOverview(
        devices: _overview?.devices ?? const <EquipmentDevice>[],
        commandHistory: [command, ...history],
      );
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
    for (final command
        in _overview?.commandHistory ?? const <CommandRecord>[]) {
      if (command.id == id) return command;
    }
    return null;
  }

  void _setCommandStatus(String id, CommandStatus status) {
    if (!mounted) return;
    final current = _overview;
    if (current == null) return;
    setState(() {
      _overview = EquipmentOverview(
        devices: current.devices,
        commandHistory: [
          for (final command in current.commandHistory)
            command.id == id ? command.copyWith(status: status) : command,
        ],
        historyHasNextPage: current.historyHasNextPage,
      );
    });
  }

  void _updateDeviceAfterCommand(EquipmentDevice device, String actionLabel) {
    if (!mounted) return;
    final current = _overview;
    if (current == null) return;
    final index = current.devices.indexWhere((item) => item.id == device.id);
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
      _overview = EquipmentOverview(
        devices: [
          for (var i = 0; i < current.devices.length; i++)
            if (i == index)
              current.devices[i].copyWith(
                powerState: state,
                lastActionLabel: '$actionLabel completed just now',
              )
            else
              current.devices[i],
        ],
        commandHistory: current.commandHistory,
        historyHasNextPage: current.historyHasNextPage,
      );
    });
  }
}

class _ReadOnlyNotice extends StatelessWidget {
  const _ReadOnlyNotice({
    required this.isRetired,
    this.isBackendRestricted = false,
  });

  final bool isRetired;
  final bool isBackendRestricted;

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
              isBackendRestricted
                  ? 'Equipment state and history are restricted to Admin accounts by the backend. This Staff account cannot view them.'
                  : isRetired
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

class _EquipmentLoadingState extends StatelessWidget {
  const _EquipmentLoadingState();

  @override
  Widget build(BuildContext context) => const SoftCard(
    child: Row(
      children: [
        SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        SizedBox(width: 12),
        Expanded(
          child: Text(
            'Loading equipment from AquaLogic…',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );
}

class _EquipmentErrorState extends StatelessWidget {
  const _EquipmentErrorState({
    required this.message,
    required this.retrying,
    required this.onRetry,
  });

  final String message;
  final bool retrying;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => SoftCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(message, style: const TextStyle(color: AppColors.text)),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: retrying ? null : onRetry,
          icon: const Icon(LucideIcons.refreshCw, size: 16),
          label: const Text('Retry'),
        ),
      ],
    ),
  );
}

class _EquipmentStaleState extends StatelessWidget {
  const _EquipmentStaleState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => SoftCard(
    child: Row(
      children: [
        const Icon(LucideIcons.cloudOff, color: AppColors.offline),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            '$message Showing the last successful data.',
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ),
        IconButton(
          tooltip: 'Retry equipment refresh',
          onPressed: onRetry,
          icon: const Icon(LucideIcons.refreshCw),
        ),
      ],
    ),
  );
}

class _EquipmentSourceState extends StatelessWidget {
  const _EquipmentSourceState({
    required this.title,
    required this.message,
    required this.onRetry,
  });

  final String title;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => SoftCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppColors.text,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          message,
          style: const TextStyle(color: AppColors.muted, fontSize: 12),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(LucideIcons.refreshCw, size: 15),
            label: const Text('Retry'),
          ),
        ),
      ],
    ),
  );
}

class _EquipmentReadOnlyBanner extends StatelessWidget {
  const _EquipmentReadOnlyBanner();

  @override
  Widget build(BuildContext context) => const SoftCard(
    child: Row(
      children: [
        Icon(LucideIcons.eye, color: AppColors.tealDark),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'Read-only equipment state from the backend. Physical controls are not available in the mobile app.',
            style: TextStyle(
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

class _EquipmentDeviceSelector extends StatelessWidget {
  const _EquipmentDeviceSelector({
    required this.devices,
    required this.selected,
    required this.onChanged,
  });

  final List<RegisteredEquipmentDevice> devices;
  final RegisteredEquipmentDevice? selected;
  final ValueChanged<RegisteredEquipmentDevice?> onChanged;

  @override
  Widget build(BuildContext context) => SoftCard(
    child: DropdownButtonFormField<String>(
      initialValue: selected?.id,
      decoration: const InputDecoration(
        labelText: 'Registered device',
        helperText: 'Choose a device to view its state and command history.',
      ),
      items: [
        for (final device in devices)
          DropdownMenuItem(
            value: device.id,
            child: Text(device.selectionLabel),
          ),
      ],
      onChanged: (id) {
        for (final device in devices) {
          if (device.id == id) {
            onChanged(device);
            return;
          }
        }
      },
    ),
  );
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
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  command.actionLabel,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
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
        : device.isPump
        ? 'Run now'
        : 'Unavailable';
    final icon = switch (device.kind) {
      EquipmentKind.uv => LucideIcons.shieldCheck,
      EquipmentKind.led => LucideIcons.lightbulb,
      EquipmentKind.feeder => LucideIcons.utensils,
      EquipmentKind.pumpA || EquipmentKind.pumpB => LucideIcons.droplets,
      EquipmentKind.unknown => LucideIcons.circleHelp,
    };

    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
              final stackConnection =
                  textScale > 1.5 || constraints.maxWidth < 270;
              final identity = Row(
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
                            fontWeight: FontWeight.w700,
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
                ],
              );
              final connection = DeviceConnectionBadge(
                status: device.connection,
                compact: true,
              );
              if (stackConnection) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    identity,
                    Padding(
                      padding: const EdgeInsets.only(left: 53, top: 8),
                      child: SizedBox(
                        width: constraints.maxWidth - 53,
                        child: FittedBox(
                          alignment: Alignment.centerLeft,
                          fit: BoxFit.scaleDown,
                          child: connection,
                        ),
                      ),
                    ),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: identity),
                  connection,
                ],
              );
            },
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
          if (device.stateRefreshedAt != null) ...[
            const SizedBox(height: 5),
            Text(
              'State last reported: ${formatLocalTimestamp(device.stateRefreshedAt!)}',
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (canManage && device.kind != EquipmentKind.unknown) ...[
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
            fontWeight: FontWeight.w700,
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
              fontWeight: FontWeight.w700,
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
                    fontWeight: FontWeight.w700,
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

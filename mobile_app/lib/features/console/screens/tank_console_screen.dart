import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../controllers/console_controller.dart';
import '../data/console_repository.dart';
import '../models/console_command.dart';
import '../models/console_state.dart';
import '../platform/console_display_session.dart';
import '../widgets/console_command_sheet.dart';
import '../widgets/console_equipment_card.dart';
import '../widgets/console_metric_card.dart';
import '../widgets/console_settings_sheet.dart';
import '../widgets/console_status_bar.dart';
import '../widgets/console_style.dart';
import '../widgets/console_warning_card.dart';

class TankConsoleScreen extends StatefulWidget {
  const TankConsoleScreen({
    super.key,
    required this.repository,
    this.ownsRepository = false,
    this.displaySession,
  });
  final ConsoleRepository repository;
  final bool ownsRepository;
  final ConsoleDisplaySession? displaySession;
  @override
  State<TankConsoleScreen> createState() => _TankConsoleScreenState();
}

class _TankConsoleScreenState extends State<TankConsoleScreen> {
  late final ConsoleController _controller;
  late final ConsoleDisplaySession _display;
  bool _allowExit = false;
  bool _exitDialogOpen = false;

  @override
  void initState() {
    super.initState();
    _display = widget.displaySession ?? AndroidConsoleDisplaySession();
    unawaited(_display.enter());
    _controller = ConsoleController(widget.repository)..start();
  }

  @override
  void dispose() {
    _controller.dispose();
    unawaited(_display.exit());
    if (widget.ownsRepository) unawaited(widget.repository.dispose());
    super.dispose();
  }

  Future<void> _requestExit() async {
    if (_exitDialogOpen) return;
    _exitDialogOpen = true;
    final exit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Exit Console Mode?'),
        content: const Text(
          'Return to the normal AquaLogic app. Console display settings will be restored.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Stay in console'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Exit console'),
          ),
        ],
      ),
    );
    _exitDialogOpen = false;
    if (exit != true || !mounted) return;
    await _display.exit();
    if (!mounted) return;
    setState(() => _allowExit = true);
    // PopScope must receive canPop=true before the programmatic pop.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  Future<void> _sheet(Widget child) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: ConsoleStyle.surface,
    constraints: const BoxConstraints(maxWidth: 620),
    builder: (context) => Theme(
      data: ConsoleStyle.theme(context),
      child: SafeArea(child: SingleChildScrollView(child: child)),
    ),
  );

  void _controls(String title, ConsoleAction? action, {bool readOnly = false}) {
    _sheet(
      ConsoleCommandSheet(
        controller: _controller,
        title: title,
        action: action,
        readOnly: readOnly,
      ),
    );
  }

  void _settings() {
    _sheet(
      ConsoleSettingsSheet(
        controller: _controller,
        onExit: () {
          Navigator.of(context).pop();
          _requestExit();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: ConsoleStyle.theme(context),
    child: PopScope(
      canPop: _allowExit,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _requestExit();
      },
      child: Scaffold(
        backgroundColor: ConsoleStyle.background,
        body: SafeArea(
          child: ListenableBuilder(
            listenable: _controller,
            builder: (context, _) {
              final state = _controller.state;
              if (state == null) {
                return Center(
                  child: _controller.error == null
                      ? const CircularProgressIndicator()
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_controller.error!),
                            TextButton(
                              onPressed: _controller.retry,
                              child: const Text('Retry'),
                            ),
                            TextButton(
                              onPressed: _requestExit,
                              child: const Text('Exit Console Mode'),
                            ),
                          ],
                        ),
                );
              }
              return LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 640;
                  final scaledText =
                      MediaQuery.textScalerOf(context).scale(16) > 20;
                  final minimumHeight = wide
                      ? scaledText
                            ? 500.0
                            : 380.0
                      : 860.0;
                  final height = math.max(constraints.maxHeight, minimumHeight);
                  final dashboard = SizedBox(
                    height: height,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                      child: _dashboard(state, wide, scaledText),
                    ),
                  );
                  return constraints.maxHeight < minimumHeight
                      ? SingleChildScrollView(child: dashboard)
                      : dashboard;
                },
              );
            },
          ),
        ),
      ),
    ),
  );

  Widget _dashboard(ConsoleState state, bool wide, bool scaledText) {
    final equipment = state.equipment;
    final metrics = [
      ConsoleMetricCard(
        label: 'Temperature',
        value: state.temperature.toStringAsFixed(1),
        unit: '°C',
        icon: Icons.thermostat_outlined,
        stale: !state.localConnected,
      ),
      ConsoleMetricCard(
        label: 'pH',
        value: state.ph.toStringAsFixed(2),
        unit: '',
        icon: Icons.water_drop_outlined,
        stale: !state.localConnected,
        attention: state.quality != ConsoleWaterQuality.normal,
      ),
      ConsoleMetricCard(
        label: 'TDS',
        value: state.tds.toStringAsFixed(0),
        unit: 'ppm',
        icon: Icons.bubble_chart_outlined,
        stale: !state.localConnected,
      ),
      ConsoleMetricCard(
        label: 'Turbidity',
        value: state.turbidity.toStringAsFixed(1),
        unit: 'NTU',
        icon: Icons.waves_outlined,
        stale: !state.localConnected,
      ),
    ];
    final controls = [
      ConsoleEquipmentCard(
        key: const ValueKey('console-light'),
        label: 'Lighting',
        status: !equipment.lightConfirmed
            ? 'UNKNOWN'
            : equipment.lightOn
            ? 'ON'
            : 'OFF',
        icon: Icons.light_mode_outlined,
        onTap: _controller.canCommand
            ? () => _controls('Lighting', ConsoleAction.lightOff)
            : null,
      ),
      ConsoleEquipmentCard(
        key: const ValueKey('console-uv'),
        label: 'UV',
        status: !equipment.uvConfirmed
            ? 'UNKNOWN'
            : equipment.uvOn
            ? 'ON'
            : 'OFF',
        icon: Icons.flare,
        onTap: _controller.canCommand
            ? () => _controls('UV sterilizer', ConsoleAction.uvOff)
            : null,
      ),
      ConsoleEquipmentCard(
        key: const ValueKey('console-feeder'),
        label: 'Feeder',
        status: !equipment.feederConfirmed
            ? 'UNKNOWN'
            : equipment.feederRunning
            ? 'RUNNING'
            : 'READY',
        icon: Icons.set_meal_outlined,
        onTap: _controller.canCommand
            ? () => _controls('Feeder', ConsoleAction.feed)
            : null,
      ),
      ConsoleEquipmentCard(
        key: const ValueKey('console-pump-a'),
        label: 'Pump A',
        status: equipment.pumpAStatus,
        icon: Icons.science_outlined,
        readOnly: true,
        onTap: () => _controls('Pump A', null, readOnly: true),
      ),
      ConsoleEquipmentCard(
        key: const ValueKey('console-pump-b'),
        label: 'Pump B',
        status: equipment.pumpBStatus,
        icon: Icons.science_outlined,
        readOnly: true,
        onTap: () => _controls('Pump B', null, readOnly: true),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: scaledText ? 70 : 48,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  state.tankName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Icon(
                Icons.water_drop_outlined,
                size: 28,
                color: ConsoleStyle.accent,
              ),
              const SizedBox(width: 7),
              if (wide)
                Text(
                  'AquaLogic',
                  style: TextStyle(
                    height: 1,
                    color: ConsoleStyle.accent,
                    fontSize: wide ? 25 : 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              const Spacer(),
              if (wide)
                Text(
                  state.localConnected ? 'LOCAL ONLINE' : 'LOCAL OFFLINE',
                  style: TextStyle(
                    color: state.localConnected
                        ? ConsoleStyle.good
                        : ConsoleStyle.warning,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              IconButton(
                key: const ValueKey('console-settings'),
                tooltip: 'Console settings',
                onPressed: _settings,
                icon: const Icon(Icons.settings_outlined),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          flex: wide ? 3 : 4,
          child: wide
              ? _row(metrics)
              : GridView.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.4,
                  physics: const NeverScrollableScrollPhysics(),
                  children: metrics,
                ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: scaledText ? 80 : 52,
          child: ConsoleWarningCard(state: state, onRetry: _controller.retry),
        ),
        const SizedBox(height: 8),
        Expanded(
          flex: 3,
          child: wide
              ? _row(controls)
              : GridView.count(
                  crossAxisCount: 3,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.3,
                  physics: const NeverScrollableScrollPhysics(),
                  children: controls,
                ),
        ),
        const SizedBox(height: 10),
        if (_controller.error != null)
          Text(
            _controller.error!,
            style: const TextStyle(color: ConsoleStyle.warning),
          ),
        SizedBox(
          height: wide
              ? scaledText
                    ? 90
                    : 46
              : 90,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ConsoleStatusBar(state: state),
              const SizedBox(height: 4),
              Row(
                children: [
                  if (state.isSimulated)
                    const Text(
                      'Prototype · simulated data',
                      style: TextStyle(
                        fontSize: 12,
                        color: ConsoleStyle.accent,
                      ),
                    ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Text(
                      state.command == null
                          ? 'COMMAND · IDLE'
                          : 'COMMAND · ${state.command!.status.label} — ${state.command!.message}',
                      key: const ValueKey('console-command-status'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1,
                        color: ConsoleStyle.muted,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(List<Widget> children) => Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var index = 0; index < children.length; index++) ...[
        if (index > 0) const SizedBox(width: 10),
        Expanded(child: children[index]),
      ],
    ],
  );
}

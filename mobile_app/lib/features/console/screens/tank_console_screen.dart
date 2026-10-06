import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../controllers/console_controller.dart';
import '../data/console_repository.dart';
import '../models/console_command.dart';
import '../models/console_state.dart';
import '../platform/console_display_session.dart';
import '../widgets/console_command_sheet.dart';
import '../widgets/console_pump_sheet.dart';
import '../widgets/console_equipment_card.dart';
import '../widgets/console_metric_card.dart';
import '../widgets/console_panel.dart';
import '../widgets/console_settings_sheet.dart';
import '../widgets/console_connection_indicator.dart';
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
  bool _panelOpen = false;
  // Locate tiles so a panel can morph out of the one that was tapped.
  final _origins = {
    for (final id in ['light', 'uv', 'feeder', 'pump-a', 'pump-b', 'settings'])
      id: GlobalKey(debugLabel: 'console-origin-$id'),
  };

  Rect? _rectOf(String id) {
    final box = _origins[id]?.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

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

  Future<void> _sheet(Widget child, String origin) async {
    final rect = _rectOf(origin);
    setState(() => _panelOpen = true);
    await showConsolePanel(context, child, origin: rect);
    if (mounted) setState(() => _panelOpen = false);
  }

  void _controls(
    String origin,
    String title,
    IconData icon,
    ConsoleAction? action, {
    bool readOnly = false,
  }) {
    _sheet(
      ConsoleCommandSheet(
        controller: _controller,
        title: title,
        icon: icon,
        action: action,
        readOnly: readOnly,
      ),
      origin,
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
      'settings',
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
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -1.4),
              radius: 1.4,
              colors: [Color(0xFF0E2232), ConsoleStyle.background],
            ),
          ),
          child: AnimatedScale(
            scale: _panelOpen ? .975 : 1,
            duration: const Duration(milliseconds: 420),
            curve: _panelOpen
                ? const ConsoleSpringCurve()
                : Curves.easeOutCubic,
            child: SafeArea(
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
                      final height = math.max(
                        constraints.maxHeight,
                        minimumHeight,
                      );
                      final dashboard = SizedBox(
                        height: height,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
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
      ),
    ),
  );

  Widget _dashboard(ConsoleState state, bool wide, bool scaledText) {
    final equipment = state.equipment;
    final metrics = [
      ConsoleMetricCard(
        label: 'Temperature',
        value: state.temperature?.toStringAsFixed(1) ?? '—',
        unit: '°C',
        icon: Icons.thermostat_outlined,
        stale: state.readingsStale,
        isSimulated: state.isSimulated,
        reportedStatus: state.sensorStatuses['temp'],
      ),
      ConsoleMetricCard(
        label: 'pH',
        value: state.ph?.toStringAsFixed(2) ?? '—',
        unit: '',
        icon: Icons.water_drop_outlined,
        stale: state.readingsStale,
        isSimulated: state.isSimulated,
        reportedStatus: state.sensorStatuses['ph'],
        attention: state.isSimulated
            ? state.quality != ConsoleWaterQuality.normal
            : state.sensorStatuses['ph'] != null &&
                  state.sensorStatuses['ph'] != 'NORMAL',
      ),
      ConsoleMetricCard(
        label: 'TDS',
        value: state.tds?.toStringAsFixed(0) ?? '—',
        unit: 'ppm',
        icon: Icons.bubble_chart_outlined,
        stale: state.readingsStale,
        isSimulated: state.isSimulated,
        reportedStatus: state.sensorStatuses['tds'],
      ),
      ConsoleMetricCard(
        label: 'Turbidity',
        value: state.turbidity?.toStringAsFixed(1) ?? '—',
        unit: 'NTU',
        icon: Icons.waves_outlined,
        stale: state.readingsStale,
        isSimulated: state.isSimulated,
        reportedStatus: state.sensorStatuses['turbidity'],
      ),
    ];
    final controls = [
      KeyedSubtree(
        key: _origins['light'],
        child: ConsoleEquipmentCard(
          key: const ValueKey('console-light'),
          label: 'Lighting',
          status: !equipment.lightConfirmed
              ? 'Unknown'
              : equipment.lightOn
              ? 'On'
              : 'Off',
          icon: Icons.light_mode_outlined,
          active: equipment.lightConfirmed && equipment.lightOn,
          onTap: !state.isSimulated || _controller.canCommand
              ? () => _controls(
                  'light',
                  'Lighting',
                  Icons.light_mode_outlined,
                  ConsoleAction.lightOff,
                )
              : null,
        ),
      ),
      KeyedSubtree(
        key: _origins['uv'],
        child: ConsoleEquipmentCard(
          key: const ValueKey('console-uv'),
          label: 'UV',
          status: !equipment.uvConfirmed
              ? 'Unknown'
              : equipment.uvOn
              ? 'On'
              : 'Off',
          icon: Icons.flare,
          active: equipment.uvConfirmed && equipment.uvOn,
          onTap: !state.isSimulated || _controller.canCommand
              ? () => _controls(
                  'uv',
                  'UV sterilizer',
                  Icons.flare,
                  ConsoleAction.uvOff,
                )
              : null,
        ),
      ),
      KeyedSubtree(
        key: _origins['feeder'],
        child: ConsoleEquipmentCard(
          key: const ValueKey('console-feeder'),
          label: 'Feeder',
          status: !equipment.feederConfirmed
              ? 'Unknown'
              : equipment.feederRunning
              ? 'Running'
              : 'Ready',
          icon: Icons.set_meal_outlined,
          active: equipment.feederConfirmed && equipment.feederRunning,
          onTap: !state.isSimulated || _controller.canCommand
              ? () => _controls(
                  'feeder',
                  'Feeder',
                  Icons.set_meal_outlined,
                  ConsoleAction.feed,
                )
              : null,
        ),
      ),
      KeyedSubtree(
        key: _origins['pump-a'],
        child: ConsoleEquipmentCard(
          key: const ValueKey('console-pump-a'),
          label: 'Pump A',
          status: _title(equipment.pumpAStatus),
          icon: Icons.science_outlined,
          readOnly: !widget.repository.supportsPumpControls,
          onTap: widget.repository.supportsPumpControls
              ? () => _sheet(
                  ConsolePumpSheet(controller: _controller, pumpA: true),
                  'pump-a',
                )
              : () => _controls(
                  'pump-a',
                  'Pump A',
                  Icons.science_outlined,
                  null,
                  readOnly: true,
                ),
        ),
      ),
      KeyedSubtree(
        key: _origins['pump-b'],
        child: ConsoleEquipmentCard(
          key: const ValueKey('console-pump-b'),
          label: 'Pump B',
          status: _title(equipment.pumpBStatus),
          icon: Icons.science_outlined,
          readOnly: !widget.repository.supportsPumpControls,
          onTap: widget.repository.supportsPumpControls
              ? () => _sheet(
                  ConsolePumpSheet(controller: _controller, pumpA: false),
                  'pump-b',
                )
              : () => _controls(
                  'pump-b',
                  'Pump B',
                  Icons.science_outlined,
                  null,
                  readOnly: true,
                ),
        ),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: scaledText ? 70 : 56,
          child: _header(state, wide && !scaledText),
        ),
        const SizedBox(height: 8),
        Expanded(flex: wide ? 5 : 4, child: _readings(metrics, wide)),
        const SizedBox(height: 14),
        SizedBox(
          height: scaledText ? 84 : (wide ? 60 : 72),
          child: ConsoleWarningCard(state: state, onRetry: _controller.retry),
        ),
        const SizedBox(height: 14),
        Expanded(
          flex: 3,
          child: wide
              ? _row(controls, gap: 12)
              : GridView.count(
                  crossAxisCount: 3,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.3,
                  physics: const NeverScrollableScrollPhysics(),
                  children: controls,
                ),
        ),
        if (_controller.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _controller.error!,
              style: const TextStyle(color: ConsoleStyle.warning),
            ),
          ),
        SizedBox(height: scaledText ? 56 : 40, child: _footer(state)),
      ],
    );
  }

  Widget _header(ConsoleState state, bool wide) {
    final updated = state.observedAt == null
        ? 'unavailable'
        : TimeOfDay.fromDateTime(state.observedAt!).format(context);
    return Row(
      children: [
        const Icon(
          Icons.water_drop_outlined,
          size: 24,
          color: ConsoleStyle.accent,
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            state.tankName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 26,
              height: 1,
              fontWeight: FontWeight.w600,
              letterSpacing: -.3,
            ),
          ),
        ),
        if (wide && MediaQuery.sizeOf(context).width >= 960) ...[
          const SizedBox(width: 20),
          Text(
            'Updated $updated',
            style: const TextStyle(
              fontSize: 14,
              color: ConsoleStyle.faint,
              fontFeatures: ConsoleStyle.tabular,
            ),
          ),
        ],
        if (wide && MediaQuery.sizeOf(context).width >= 960) ...[
          const Spacer(),
          const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.water_drop, size: 16, color: ConsoleStyle.accent),
              SizedBox(width: 6),
              Text(
                'AquaLogic',
                style: TextStyle(
                  fontSize: 15,
                  height: 1,
                  fontWeight: FontWeight.w600,
                  letterSpacing: .4,
                  color: ConsoleStyle.accent,
                ),
              ),
            ],
          ),
        ],
        const Spacer(),
        ConsoleConnectionIndicator(
          label: 'Local',
          connected: state.localConnected,
          status: state.isSimulated ? null : _title(state.connection.name),
          compact: true,
        ),
        const SizedBox(width: 20),
        ConsoleConnectionIndicator(
          label: 'Cloud',
          connected: state.cloudConnected,
          compact: true,
        ),
        const SizedBox(width: 12),
        KeyedSubtree(
          key: _origins['settings'],
          child: IconButton(
            key: const ValueKey('console-settings'),
            tooltip: 'Console settings',
            onPressed: _settings,
            iconSize: 24,
            constraints: const BoxConstraints.tightFor(width: 48, height: 48),
            icon: const Icon(Icons.tune_rounded),
          ),
        ),
      ],
    );
  }

  /// Four readings share one slab separated by hairlines; the cyan line along
  /// the bottom edge mirrors the enclosure's LED strip.
  Widget _readings(List<Widget> metrics, bool wide) {
    const divider = VerticalDivider(
      width: 1,
      thickness: 1,
      indent: 24,
      endIndent: 24,
      color: ConsoleStyle.hairline,
    );
    final Widget body = wide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < metrics.length; index++) ...[
                if (index > 0) divider,
                Expanded(child: metrics[index]),
              ],
            ],
          )
        : Column(
            children: [
              for (var row = 0; row < 2; row++) ...[
                if (row > 0)
                  const Divider(
                    height: 1,
                    indent: 20,
                    endIndent: 20,
                    color: ConsoleStyle.hairline,
                  ),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: metrics[row * 2]),
                      divider,
                      Expanded(child: metrics[row * 2 + 1]),
                    ],
                  ),
                ),
              ],
            ],
          );
    return RepaintBoundary(
      child: Container(
        decoration: ConsoleStyle.panelDecoration(),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Expanded(child: body),
            Container(
              height: 2,
              margin: const EdgeInsets.symmetric(horizontal: 24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    ConsoleStyle.accent.withValues(alpha: 0),
                    ConsoleStyle.accent,
                    ConsoleStyle.accent.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _footer(ConsoleState state) {
    const meta = TextStyle(fontSize: 13, height: 1, color: ConsoleStyle.faint);
    final uncertain = state.uncertainCommands;
    final command = uncertain.firstOrNull ?? state.command;
    return Row(
      children: [
        if (state.isSimulated) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: ConsoleStyle.warning.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              'Simulated data',
              style: meta.copyWith(
                color: ConsoleStyle.warning.withValues(alpha: .85),
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 14),
        ],
        Expanded(
          child: Text(
            command == null
                ? state.isSimulated
                      ? 'Command idle'
                      : 'Live ESP32 · local control · device reports authoritative'
                : 'Command ${command.status.label.toLowerCase()} — ${command.message}',
            key: const ValueKey('console-command-status'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: command?.status == ConsoleCommandStatus.unknown
                ? meta.copyWith(color: ConsoleStyle.warning)
                : meta,
          ),
        ),
      ],
    );
  }

  Widget _row(List<Widget> children, {double gap = 10}) => Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var index = 0; index < children.length; index++) ...[
        if (index > 0) SizedBox(width: gap),
        Expanded(child: children[index]),
      ],
    ],
  );

  static String _title(String value) => value.isEmpty
      ? value
      : value[0].toUpperCase() + value.substring(1).toLowerCase();
}

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
    this.initiallyLocked = true,
    this.idleTimeout = const Duration(seconds: 60),
  });
  final ConsoleRepository repository;
  final bool ownsRepository;
  final ConsoleDisplaySession? displaySession;

  /// Starts in Display mode: readings only, controls behind hold-to-unlock.
  final bool initiallyLocked;

  /// Control mode returns to Display mode after this long without a touch.
  final Duration idleTimeout;
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

  // Display/Control mode. The lock guards against accidental touches (wiping
  // the glass, leaning on the tank); authorization still lives elsewhere.
  late bool _locked = widget.initiallyLocked;
  Timer? _idle;
  Timer? _hintTimer;
  String? _hint;
  // Failed or unknown outcomes stay flagged on a tile until its panel is seen.
  final _acknowledged = <String>{};

  @override
  void initState() {
    super.initState();
    _display = widget.displaySession ?? AndroidConsoleDisplaySession();
    unawaited(_display.enter());
    _controller = ConsoleController(widget.repository)..start();
  }

  bool get _commandPending =>
      _controller.busy ||
      (_controller.state?.commands.values.any((c) => c.status.isPending) ??
          false);

  void _touched() {
    if (_locked) return;
    _idle?.cancel();
    _idle = Timer(widget.idleTimeout, _relockWhenIdle);
  }

  // Never relock under an open panel or an unconfirmed command; try again later.
  void _relockWhenIdle() {
    if (!mounted) return;
    if (_panelOpen || _commandPending) return _touched();
    setState(() => _locked = true);
  }

  void _setLocked(bool locked) {
    setState(() {
      _locked = locked;
      _hint = null;
    });
    if (locked) {
      _idle?.cancel();
    } else {
      _touched();
    }
  }

  void _showHint(String hint) {
    _hintTimer?.cancel();
    setState(() => _hint = hint);
    _hintTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _hint = null);
    });
  }

  @override
  void dispose() {
    _idle?.cancel();
    _hintTimer?.cancel();
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
    if (!mounted) return;
    setState(() => _panelOpen = false);
    _touched();
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
        body: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) {
            if (_locked) {
              _showHint('Hold the lock to use controls');
            } else {
              _touched();
            }
          },
          child: DecoratedBox(
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
                            child: _dashboard(
                              state,
                              wide,
                              scaledText,
                              height - 24,
                            ),
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
    ),
  );

  Widget _dashboard(
    ConsoleState state,
    bool wide,
    bool scaledText,
    double available,
  ) {
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
        critical: state.quality == ConsoleWaterQuality.critical,
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
    final tiles = [
      _switchTile(
        state,
        id: 'light',
        label: 'Lighting',
        panelTitle: 'Lighting',
        icon: Icons.light_mode_outlined,
        actuator: ConsoleActuator.light,
        confirmed: equipment.lightConfirmed,
        on: equipment.lightOn,
        onAction: ConsoleAction.lightOn,
        offAction: ConsoleAction.lightOff,
      ),
      _switchTile(
        state,
        id: 'uv',
        label: 'UV',
        panelTitle: 'UV sterilizer',
        icon: Icons.flare,
        actuator: ConsoleActuator.uv,
        confirmed: equipment.uvConfirmed,
        on: equipment.uvOn,
        onAction: ConsoleAction.uvOn,
        offAction: ConsoleAction.uvOff,
      ),
      _feederTile(state),
      _pumpTile(state, pumpA: true),
      _pumpTile(state, pumpA: false),
    ];
    final strip = _EquipmentStrip(
      items: [
        (
          Icons.light_mode_outlined,
          'Lighting',
          _onOff(equipment.lightConfirmed, equipment.lightOn),
          equipment.lightConfirmed && equipment.lightOn,
        ),
        (
          Icons.flare,
          'UV',
          _onOff(equipment.uvConfirmed, equipment.uvOn),
          equipment.uvConfirmed && equipment.uvOn,
        ),
        (
          Icons.set_meal_outlined,
          'Feeder',
          !equipment.feederConfirmed
              ? 'Unknown'
              : equipment.feederRunning
              ? 'Feeding'
              : equipment.lastFed == null
              ? 'Ready'
              : 'Fed ${equipment.lastFed}',
          equipment.feederConfirmed && equipment.feederRunning,
        ),
        (
          Icons.science_outlined,
          'Pump A',
          _title(equipment.pumpAStatus),
          equipment.pumpA.active == true,
        ),
        (
          Icons.science_outlined,
          'Pump B',
          _title(equipment.pumpBStatus),
          equipment.pumpB.active == true,
        ),
      ],
    );
    // Tiles take up to 3/8 of the flexible height (the old 5:3 split with the
    // readings), capped so tall screens keep big readings.
    final fixed =
        (scaledText ? 70 : 56) +
        8 +
        14 +
        14 +
        (scaledText ? 56 : 40) +
        6 +
        (scaledText ? 84 : 60);
    final controlsHeight = ((available - fixed) * 3 / 8).clamp(
      60.0,
      scaledText ? 172.0 : 150.0,
    );
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
        // Display mode keeps a one-line equipment summary; Control mode grows
        // it into the tiles. Readings take whatever height is left.
        if (wide)
          AnimatedContainer(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            height: _locked ? 40 : controlsHeight,
            // Each child keeps its own height while the area resizes, so the
            // crossfade clips instead of squeezing the tiles.
            child: ClipRect(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                layoutBuilder: (current, previous) => Stack(
                  alignment: Alignment.topCenter,
                  children: [...previous, ?current],
                ),
                child: _locked
                    ? OverflowBox(
                        key: const ValueKey('strip'),
                        alignment: Alignment.topCenter,
                        minHeight: 40,
                        maxHeight: 40,
                        child: strip,
                      )
                    : OverflowBox(
                        key: const ValueKey('tiles'),
                        alignment: Alignment.topCenter,
                        minHeight: controlsHeight,
                        maxHeight: controlsHeight,
                        child: _row(tiles, gap: 12),
                      ),
              ),
            ),
          )
        else if (_locked)
          strip
        else
          Expanded(
            flex: 3,
            child: GridView.count(
              crossAxisCount: 3,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.3,
              physics: const NeverScrollableScrollPhysics(),
              children: tiles,
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
        // Keeps the footer clear of the enclosure's lower bezel.
        const SizedBox(height: 6),
      ],
    );
  }

  static String _onOff(bool confirmed, bool on) =>
      !confirmed ? 'Unknown' : (on ? 'On' : 'Off');

  bool _flagged(ConsoleCommand? command) =>
      command != null &&
      !_acknowledged.contains(command.id) &&
      (command.status == ConsoleCommandStatus.failed ||
          command.status == ConsoleCommandStatus.rejected ||
          command.status == ConsoleCommandStatus.unknown);

  String _flagLabel(ConsoleCommand command) =>
      command.status == ConsoleCommandStatus.unknown
      ? 'Outcome unknown'
      : command.status == ConsoleCommandStatus.rejected
      ? 'Command rejected'
      : 'Command failed';

  void _acknowledge(ConsoleActuator actuator) {
    final command = _controller.state?.commands[actuator];
    if (command != null) _acknowledged.add(command.id);
  }

  /// Lighting and UV: one tap toggles. The tile shows the pending verb until
  /// the device confirms; it never shows the new state optimistically.
  Widget _switchTile(
    ConsoleState state, {
    required String id,
    required String label,
    required String panelTitle,
    required IconData icon,
    required ConsoleActuator actuator,
    required bool confirmed,
    required bool on,
    required ConsoleAction onAction,
    required ConsoleAction offAction,
  }) {
    final command = state.commands[actuator];
    final pending = command?.status.isPending == true;
    final flagged = _flagged(command);
    final next = on ? offAction : onAction;
    void openPanel() {
      _acknowledge(actuator);
      _controls(id, panelTitle, icon, offAction);
    }

    return KeyedSubtree(
      key: _origins[id == 'light' ? 'light' : 'uv'],
      child: ConsoleEquipmentCard(
        key: ValueKey('console-$id'),
        label: label,
        status: pending
            ? (command!.action == onAction ? 'Turning on…' : 'Turning off…')
            : _onOff(confirmed, on),
        icon: icon,
        active: confirmed && on && !pending,
        pending: pending,
        caption: flagged ? _flagLabel(command!) : 'Tap to toggle',
        alert: flagged,
        onTap: () {
          if (pending) return;
          // Anything uncertain goes through the panel, which explains why.
          if (flagged || !confirmed || !_controller.canSubmit(next)) {
            openPanel();
          } else {
            unawaited(_controller.submit(next));
          }
        },
        onMore: openPanel,
      ),
    );
  }

  /// Feeder: press and hold to feed. A short tap does nothing.
  Widget _feederTile(ConsoleState state) {
    final equipment = state.equipment;
    final command = state.commands[ConsoleActuator.feeder];
    final pending = command?.status.isPending == true;
    final flagged = _flagged(command);
    final ready =
        equipment.feederConfirmed &&
        !equipment.feederRunning &&
        !flagged &&
        _controller.canSubmit(ConsoleAction.feed);
    void openPanel() {
      _acknowledge(ConsoleActuator.feeder);
      _controls(
        'feeder',
        'Feeder',
        Icons.set_meal_outlined,
        ConsoleAction.feed,
      );
    }

    return KeyedSubtree(
      key: _origins['feeder'],
      child: ConsoleEquipmentCard(
        key: const ValueKey('console-feeder'),
        label: 'Feeder',
        status: pending || equipment.feederRunning
            ? 'Feeding…'
            : !equipment.feederConfirmed
            ? 'Unknown'
            : 'Ready',
        icon: Icons.set_meal_outlined,
        active: equipment.feederConfirmed && equipment.feederRunning,
        pending: pending,
        caption: flagged
            ? _flagLabel(command!)
            : ready
            ? 'Hold to feed'
            : 'Open for details',
        alert: flagged,
        onHold: ready
            ? () => unawaited(_controller.submit(ConsoleAction.feed))
            : null,
        onTap: ready ? () => _showHint('Hold for 1 second to feed') : openPanel,
        onMore: openPanel,
      ),
    );
  }

  /// Pumps always open their panel; dosing stays deliberate.
  Widget _pumpTile(ConsoleState state, {required bool pumpA}) {
    final id = pumpA ? 'pump-a' : 'pump-b';
    final label = pumpA ? 'Pump A' : 'Pump B';
    final actuator = pumpA ? ConsoleActuator.pumpA : ConsoleActuator.pumpB;
    final command = state.commands[actuator];
    final flagged = _flagged(command);
    final supported = widget.repository.supportsPumpControls;
    return KeyedSubtree(
      key: _origins[id],
      child: ConsoleEquipmentCard(
        key: ValueKey('console-$id'),
        label: label,
        status: _title(
          pumpA ? state.equipment.pumpAStatus : state.equipment.pumpBStatus,
        ),
        icon: Icons.science_outlined,
        active:
            (pumpA ? state.equipment.pumpA : state.equipment.pumpB).active ==
            true,
        pending: command?.status.isPending == true,
        caption: flagged
            ? _flagLabel(command!)
            : supported
            ? 'Open controls'
            : 'Monitoring only',
        alert: flagged,
        readOnly: !supported,
        onTap: () {
          _acknowledge(actuator);
          if (supported) {
            _sheet(ConsolePumpSheet(controller: _controller, pumpA: pumpA), id);
          } else {
            _controls(id, label, Icons.science_outlined, null, readOnly: true);
          }
        },
      ),
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
          label: state.isSimulated
              ? 'Simulated'
              : _title(state.connection.name),
          connected: state.localConnected,
          compact: true,
        ),
        const SizedBox(width: 16),
        _LockChip(locked: _locked, onChanged: _setLocked, compact: !wide),
        if (!_locked) ...[
          const SizedBox(width: 4),
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
    const meta = TextStyle(fontSize: 14, height: 1, color: ConsoleStyle.faint);
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
        if (_hint != null)
          Expanded(
            child: Row(
              key: const ValueKey('console-hint'),
              children: [
                Icon(
                  _locked ? Icons.lock_outline : Icons.touch_app_outlined,
                  size: 16,
                  color: ConsoleStyle.accent,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    _hint!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: meta.copyWith(color: ConsoleStyle.text),
                  ),
                ),
              ],
            ),
          )
        else
          Expanded(
            child: Text(
              command == null
                  ? state.isSimulated
                        ? 'Command idle'
                        : 'Live · connected to the tank controller'
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

/// Display-mode summary: one line, readable from across the room.
class _EquipmentStrip extends StatelessWidget {
  const _EquipmentStrip({required this.items});
  final List<(IconData, String, String, bool)> items;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (final (icon, label, status, active) in items)
        Expanded(
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: active ? ConsoleStyle.accent : ConsoleStyle.faint,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: label,
                        style: const TextStyle(color: ConsoleStyle.muted),
                      ),
                      TextSpan(
                        text: '  $status',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: active
                              ? ConsoleStyle.accent
                              : ConsoleStyle.text,
                        ),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16, height: 1),
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

/// Hold to unlock (about a second, with a fill); tap to lock again.
class _LockChip extends StatefulWidget {
  const _LockChip({
    required this.locked,
    required this.onChanged,
    this.compact = false,
  });
  final bool locked;

  /// Icon only, for narrow headers.
  final bool compact;
  final ValueChanged<bool> onChanged;

  @override
  State<_LockChip> createState() => _LockChipState();
}

class _LockChipState extends State<_LockChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _hold =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 900),
      )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _hold.value = 0;
          widget.onChanged(false);
        }
      });

  @override
  void dispose() {
    _hold.dispose();
    super.dispose();
  }

  void _release() {
    if (_hold.status != AnimationStatus.completed) _hold.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final locked = widget.locked;
    return Semantics(
      button: true,
      label: locked ? 'Hold to unlock controls' : 'Lock controls',
      excludeSemantics: true,
      child: Listener(
        onPointerDown: locked ? (_) => _hold.forward() : null,
        onPointerUp: locked ? (_) => _release() : null,
        onPointerCancel: locked ? (_) => _release() : null,
        child: GestureDetector(
          key: const ValueKey('console-lock'),
          onTap: locked ? null : () => widget.onChanged(true),
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              color: locked ? ConsoleStyle.surface : ConsoleStyle.accentDim,
              borderRadius: BorderRadius.circular(22),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _hold,
                    builder: (context, _) => FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: _hold.value,
                      child: const ColoredBox(color: Color(0x5522C3E6)),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        locked ? Icons.lock_outline : Icons.lock_open_rounded,
                        size: 20,
                        color: locked ? ConsoleStyle.text : ConsoleStyle.accent,
                      ),
                      if (!widget.compact) ...[
                        const SizedBox(width: 8),
                        Text(
                          locked ? 'Hold to unlock' : 'Lock',
                          style: TextStyle(
                            fontSize: 15,
                            height: 1,
                            fontWeight: FontWeight.w600,
                            color: locked
                                ? ConsoleStyle.text
                                : ConsoleStyle.accent,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

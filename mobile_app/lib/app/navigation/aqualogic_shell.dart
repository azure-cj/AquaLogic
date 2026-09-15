import 'dart:async';

import 'package:aqualogic/app/theme/app_colors.dart';
import 'package:aqualogic/features/alerts/screens/alerts_screen.dart';
import 'package:aqualogic/features/auth/models/auth_user.dart';
import 'package:aqualogic/features/home/screens/home_screen.dart';
import 'package:aqualogic/features/more/screens/more_screen.dart';
import 'package:aqualogic/features/sensors/data/mock_sensor_feed.dart';
import 'package:aqualogic/features/sensors/models/sensor_snapshot.dart';
import 'package:aqualogic/features/tanks/screens/tanks_screen.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class AquaLogicShell extends StatefulWidget {
  const AquaLogicShell({super.key, required this.user});

  final AuthUser user;

  @override
  State<AquaLogicShell> createState() => _AquaLogicShellState();
}

class _AquaLogicShellState extends State<AquaLogicShell> {
  static const _hideThreshold = 22.0;
  static const _showThreshold = 12.0;
  static const _nearTopThreshold = 8.0;

  var _selectedIndex = 0;
  var _isBottomNavVisible = true;
  var _downScrollDistance = 0.0;
  var _upScrollDistance = 0.0;
  var _tick = 0;
  late SensorSnapshot _snapshot;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _snapshot = MockSensorFeed.snapshot(_tick);
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      setState(() {
        _tick += 1;
        _snapshot = MockSensorFeed.snapshot(_tick);
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(
        snapshot: _snapshot,
        user: widget.user,
        onOpenAlerts: () => _selectDestination(2),
        onOpenTanks: () => _selectDestination(1),
      ),
      TanksScreen(snapshot: _snapshot, user: widget.user),
      AlertsScreen(snapshot: _snapshot),
      MoreScreen(snapshot: _snapshot, user: widget.user),
    ];

    return Scaffold(
      body: NotificationListener<ScrollNotification>(
        onNotification: _handleScrollNotification,
        child: Stack(
          fit: StackFit.expand,
          children: [
            SafeArea(
              top: false,
              child: IndexedStack(index: _selectedIndex, children: pages),
            ),
            Positioned(
              left: 14,
              right: 14,
              bottom: 0,
              child: SafeArea(
                top: false,
                left: false,
                right: false,
                minimum: const EdgeInsets.only(bottom: 10),
                child: IgnorePointer(
                  ignoring: !_isBottomNavVisible,
                  child: ExcludeSemantics(
                    excluding: !_isBottomNavVisible,
                    child: AnimatedSlide(
                      key: const ValueKey('soft-floating-dock-slide'),
                      offset: _isBottomNavVisible
                          ? Offset.zero
                          : const Offset(0, 1.25),
                      duration: const Duration(milliseconds: 210),
                      curve: Curves.easeOutCubic,
                      child: _SoftFloatingDock(
                        selectedIndex: _selectedIndex,
                        onDestinationSelected: _selectDestination,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) {
      return false;
    }

    if (notification is ScrollUpdateNotification) {
      final delta = notification.scrollDelta ?? 0;
      final pixels = notification.metrics.pixels;

      if (pixels <= _nearTopThreshold) {
        _showBottomNav();
        _resetScrollAccumulators();
        return false;
      }

      if (delta > 0) {
        _downScrollDistance += delta;
        _upScrollDistance = 0;
        if (_downScrollDistance >= _hideThreshold) {
          _hideBottomNav();
          _resetScrollAccumulators();
        }
      } else if (delta < 0) {
        _upScrollDistance += -delta;
        _downScrollDistance = 0;
        if (_upScrollDistance >= _showThreshold) {
          _showBottomNav();
          _resetScrollAccumulators();
        }
      }
    } else if (notification is ScrollEndNotification) {
      _resetScrollAccumulators();
    }

    return false;
  }

  void _selectDestination(int index) {
    _resetScrollAccumulators();
    if (_selectedIndex == index && _isBottomNavVisible) {
      return;
    }
    setState(() {
      _selectedIndex = index;
      _isBottomNavVisible = true;
    });
  }

  void _hideBottomNav() {
    if (!_isBottomNavVisible || !mounted) return;
    setState(() => _isBottomNavVisible = false);
  }

  void _showBottomNav() {
    if (_isBottomNavVisible || !mounted) return;
    setState(() => _isBottomNavVisible = true);
  }

  void _resetScrollAccumulators() {
    _downScrollDistance = 0;
    _upScrollDistance = 0;
  }
}

class _SoftFloatingDock extends StatelessWidget {
  const _SoftFloatingDock({
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const ValueKey('soft-floating-dock'),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.line.withValues(alpha: 0.9)),
        boxShadow: [
          BoxShadow(
            color: AppColors.tealDark.withValues(alpha: 0.11),
            blurRadius: 22,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        clipBehavior: Clip.antiAlias,
        borderRadius: BorderRadius.circular(22),
        child: SizedBox(
          height: 70,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: Row(
              children: [
                _SoftFloatingDestination(
                  index: 0,
                  label: 'Home',
                  icon: LucideIcons.house,
                  selected: selectedIndex == 0,
                  onTap: () => onDestinationSelected(0),
                ),
                _SoftFloatingDestination(
                  index: 1,
                  label: 'Tanks',
                  icon: LucideIcons.network,
                  selected: selectedIndex == 1,
                  onTap: () => onDestinationSelected(1),
                ),
                _SoftFloatingDestination(
                  index: 2,
                  label: 'Alerts',
                  icon: LucideIcons.bell,
                  selected: selectedIndex == 2,
                  onTap: () => onDestinationSelected(2),
                ),
                _SoftFloatingDestination(
                  index: 3,
                  label: 'More',
                  icon: LucideIcons.settings,
                  selected: selectedIndex == 3,
                  onTap: () => onDestinationSelected(3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SoftFloatingDestination extends StatelessWidget {
  const _SoftFloatingDestination({
    required this.index,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final int index;
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? AppColors.text : AppColors.muted;

    return Expanded(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final capsuleWidth = constraints.hasBoundedWidth
              ? (constraints.maxWidth - 4)
                    .clamp(0.0, constraints.maxWidth)
                    .toDouble()
              : 72.0;

          return Semantics(
            container: true,
            button: true,
            onTap: onTap,
            label: label,
            selected: selected,
            child: ExcludeSemantics(
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  key: ValueKey('soft-floating-dock-destination-$index'),
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(18),
                  overlayColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.pressed)) {
                      return AppColors.mint.withValues(alpha: 0.45);
                    }
                    if (states.contains(WidgetState.hovered)) {
                      return AppColors.mint.withValues(alpha: 0.16);
                    }
                    return Colors.transparent;
                  }),
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      height: 54,
                      width: capsuleWidth,
                      padding: const EdgeInsets.symmetric(horizontal: 7),
                      decoration: BoxDecoration(
                        color: selected ? AppColors.mint : Colors.transparent,
                        border: selected
                            ? Border.all(
                                color: AppColors.teal.withValues(alpha: 0.14),
                              )
                            : null,
                        borderRadius: BorderRadius.circular(17),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(icon, size: 20, color: foreground),
                          const SizedBox(height: 2),
                          Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: foreground,
                              fontSize: 10.5,
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

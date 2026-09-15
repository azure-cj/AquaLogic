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
import 'package:flutter/rendering.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class AquaLogicShell extends StatefulWidget {
  const AquaLogicShell({super.key, required this.user});

  final AuthUser user;

  @override
  State<AquaLogicShell> createState() => _AquaLogicShellState();
}

class _AquaLogicShellState extends State<AquaLogicShell> {
  var _selectedIndex = 0;
  var _isBottomNavVisible = true;
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
        onOpenAlerts: () {
          setState(() {
            _selectedIndex = 2;
            _isBottomNavVisible = true;
          });
        },
        onOpenTanks: () {
          setState(() {
            _selectedIndex = 1;
            _isBottomNavVisible = true;
          });
        },
      ),
      TanksScreen(snapshot: _snapshot, user: widget.user),
      AlertsScreen(snapshot: _snapshot),
      MoreScreen(snapshot: _snapshot, user: widget.user),
    ];

    return Scaffold(
      body: SafeArea(
        top: false,
        child: NotificationListener<UserScrollNotification>(
          onNotification: _handleScrollNotification,
          child: IndexedStack(index: _selectedIndex, children: pages),
        ),
      ),
      bottomNavigationBar: _AnimatedBottomNavigation(
        selectedIndex: _selectedIndex,
        isVisible: _isBottomNavVisible,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
            _isBottomNavVisible = true;
          });
        },
      ),
    );
  }

  bool _handleScrollNotification(UserScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) {
      return false;
    }

    final direction = notification.direction;
    if (direction == ScrollDirection.reverse && _isBottomNavVisible) {
      setState(() => _isBottomNavVisible = false);
    } else if (direction == ScrollDirection.forward && !_isBottomNavVisible) {
      setState(() => _isBottomNavVisible = true);
    }

    return false;
  }
}

class _AnimatedBottomNavigation extends StatelessWidget {
  const _AnimatedBottomNavigation({
    required this.selectedIndex,
    required this.isVisible,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final bool isVisible;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      key: const ValueKey('bottom-nav-shell'),
      duration: const Duration(milliseconds: 230),
      curve: Curves.easeOutCubic,
      height: isVisible ? 88 : 0,
      child: ClipRect(
        child: Align(
          alignment: Alignment.topCenter,
          heightFactor: isVisible ? 1 : 0,
          child: RepaintBoundary(
            key: const ValueKey('bottom-nav-slide'),
            child: IgnorePointer(
              ignoring: !isVisible,
              child: ExcludeSemantics(
                excluding: !isVisible,
                child: AnimatedSlide(
                  offset: isVisible ? Offset.zero : const Offset(0, 0.35),
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  child: AnimatedOpacity(
                    key: const ValueKey('bottom-nav-opacity'),
                    opacity: isVisible ? 1 : 0,
                    duration: const Duration(milliseconds: 150),
                    curve: Curves.easeOut,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(21),
                        child: NavigationBar(
                          selectedIndex: selectedIndex,
                          height: 66,
                          elevation: 6,
                          backgroundColor: Colors.white,
                          indicatorColor: AppColors.mint,
                          labelBehavior:
                              NavigationDestinationLabelBehavior.alwaysShow,
                          onDestinationSelected: onDestinationSelected,
                          destinations: const [
                            NavigationDestination(
                              icon: Icon(LucideIcons.house),
                              selectedIcon: Icon(LucideIcons.house),
                              label: 'Home',
                            ),
                            NavigationDestination(
                              icon: Icon(LucideIcons.network),
                              selectedIcon: Icon(LucideIcons.network),
                              label: 'Tanks',
                            ),
                            NavigationDestination(
                              icon: Icon(LucideIcons.bell),
                              selectedIcon: Icon(LucideIcons.bell),
                              label: 'Alerts',
                            ),
                            NavigationDestination(
                              icon: Icon(LucideIcons.settings),
                              selectedIcon: Icon(LucideIcons.settings),
                              label: 'More',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

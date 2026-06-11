import 'dart:async';
import 'package:aqualogic/app/theme/app_colors.dart';
import 'package:aqualogic/features/alerts/screens/alerts_screen.dart';
import 'package:aqualogic/features/control/screens/control_screen.dart';
import 'package:aqualogic/features/home/screens/home_screen.dart';
import 'package:aqualogic/features/more/screens/more_screen.dart';
import 'package:aqualogic/features/sensors/data/mock_sensor_feed.dart';
import 'package:aqualogic/features/sensors/models/sensor_snapshot.dart';
import 'package:aqualogic/features/tanks/screens/tanks_screen.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class AquaLogicShell extends StatefulWidget {
  const AquaLogicShell({super.key});

  @override
  State<AquaLogicShell> createState() => _AquaLogicShellState();
}

class _AquaLogicShellState extends State<AquaLogicShell> {
  var _selectedIndex = 0;
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
        onOpenAlerts: () => setState(() => _selectedIndex = 3),
      ),
      TanksScreen(snapshot: _snapshot),
      ControlScreen(snapshot: _snapshot),
      AlertsScreen(snapshot: _snapshot),
      MoreScreen(snapshot: _snapshot),
    ];

    return Scaffold(
      body: SafeArea(
        top: false,
        child: IndexedStack(index: _selectedIndex, children: pages),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: NavigationBar(
            selectedIndex: _selectedIndex,
            height: 72,
            elevation: 8,
            backgroundColor: Colors.white,
            indicatorColor: AppColors.mint,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            onDestinationSelected: (index) {
              setState(() => _selectedIndex = index);
            },
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
                icon: Icon(LucideIcons.slidersHorizontal),
                selectedIcon: Icon(LucideIcons.slidersHorizontal),
                label: 'Control',
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
    );
  }
}

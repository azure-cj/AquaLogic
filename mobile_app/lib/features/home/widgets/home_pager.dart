import 'package:aqualogic/features/home/screens/home_screen.dart';
import 'package:aqualogic/features/home/screens/today_owner_brief_screen.dart';
import 'package:aqualogic/features/sensors/models/sensor_snapshot.dart';
import 'package:flutter/material.dart';

class HomePager extends StatefulWidget {
  const HomePager({
    super.key,
    required this.snapshot,
    required this.onOpenAlerts,
    required this.onBriefVisibilityChanged,
  });

  final SensorSnapshot snapshot;
  final VoidCallback onOpenAlerts;
  final ValueChanged<bool> onBriefVisibilityChanged;

  @override
  State<HomePager> createState() => _HomePagerState();
}

class _HomePagerState extends State<HomePager> {
  static const _briefPage = 0;
  static const _homePage = 1;

  late final PageController _controller;

  @override
  void initState() {
    super.initState();
    _controller = PageController(initialPage: _homePage);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _returnToHome() {
    _controller.animateToPage(
      _homePage,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PageView(
      controller: _controller,
      onPageChanged: (page) {
        widget.onBriefVisibilityChanged(page == _briefPage);
      },
      children: [
        TodayOwnerBriefScreen(
          snapshot: widget.snapshot,
          onBackToHome: _returnToHome,
        ),
        HomeScreen(
          snapshot: widget.snapshot,
          onOpenAlerts: widget.onOpenAlerts,
        ),
      ],
    );
  }
}

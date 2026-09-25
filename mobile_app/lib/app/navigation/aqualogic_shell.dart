import 'dart:async';

import 'package:aqualogic/app/theme/app_colors.dart';
import 'package:aqualogic/features/alerts/data/mock_alert_repository.dart';
import 'package:aqualogic/features/alerts/screens/alert_detail_screen.dart';
import 'package:aqualogic/features/alerts/screens/alerts_screen.dart';
import 'package:aqualogic/features/auth/models/auth_user.dart';
import 'package:aqualogic/features/home/data/home_repository.dart';
import 'package:aqualogic/features/home/data/mock_home_repository.dart';
import 'package:aqualogic/features/home/models/home_dashboard_data.dart';
import 'package:aqualogic/features/home/screens/home_screen.dart';
import 'package:aqualogic/features/more/screens/more_screen.dart';
import 'package:aqualogic/features/sensors/data/mock_sensor_feed.dart';
import 'package:aqualogic/features/sensors/models/sensor_snapshot.dart';
import 'package:aqualogic/features/tanks/screens/tanks_screen.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class AquaLogicShell extends StatefulWidget {
  const AquaLogicShell({
    super.key,
    required this.user,
    this.homeRepository = const MockHomeRepository(),
  });

  final AuthUser user;
  final HomeRepository homeRepository;

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
  MockHomeRepository? _mockHomeRepository;
  int? _mockHomeRepositoryTick;

  @override
  void initState() {
    super.initState();
    _snapshot = MockSensorFeed.snapshot(_tick);
    if (widget.homeRepository.refreshDemoData) {
      _timer = Timer.periodic(const Duration(seconds: 4), (_) {
        setState(() {
          _tick += 1;
          _snapshot = MockSensorFeed.snapshot(_tick);
        });
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final homeRepository = _homeRepositoryForCurrentTick();
    final pages = [
      HomeScreen(
        repository: homeRepository,
        user: widget.user,
        onOpenAlerts: _openHomeAlerts,
        onOpenTanks: _openHomeTanks,
        onOpenAlert: _openHomeAttention,
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
            AnimatedPositioned(
              key: const ValueKey('soft-floating-dock-position'),
              left: 14,
              right: 14,
              bottom: _isBottomNavVisible ? 0 : -80,
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeInOutCubic,
              child: SafeArea(
                top: false,
                left: false,
                right: false,
                minimum: const EdgeInsets.only(bottom: 10),
                child: IgnorePointer(
                  ignoring: !_isBottomNavVisible,
                  child: ExcludeSemantics(
                    excluding: !_isBottomNavVisible,
                    child: AnimatedOpacity(
                      key: const ValueKey('soft-floating-dock-fade'),
                      opacity: _isBottomNavVisible ? 1 : 0,
                      duration: const Duration(milliseconds: 240),
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

  HomeRepository _homeRepositoryForCurrentTick() {
    final repository = widget.homeRepository;
    if (repository is! MockHomeRepository) return repository;
    if (_mockHomeRepository == null || _mockHomeRepositoryTick != _tick) {
      _mockHomeRepository = repository.withTick(_tick);
      _mockHomeRepositoryTick = _tick;
    }
    return _mockHomeRepository!;
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

  void _openHomeAttention(HomeAttentionItem item) {
    if (widget.homeRepository.isLiveData) {
      _showHomeDestinationNotice(
        item.type == HomeAttentionType.monitoring
            ? 'Monitoring details are not connected yet. The Alerts and Tanks screens remain demo-backed until M3/M4.'
            : 'Alert details are not connected yet. The Alerts screen remains demo-backed until M4.',
      );
      return;
    }
    final sourceId = item.sourceId;
    if (sourceId == null) {
      _showMissingHomeAttention(item.type);
      return;
    }

    final alertData = const MockAlertRepository().load(snapshot: _snapshot);
    if (item.type == HomeAttentionType.waterQuality) {
      for (final alert in alertData.waterQualityAlerts) {
        if (alert.id == sourceId) {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => AlertDetailScreen(alert: alert),
            ),
          );
          return;
        }
      }
    } else {
      for (final incident in alertData.monitoringIncidents) {
        if (incident.id == sourceId) {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => AlertsScreen(
                snapshot: _snapshot,
                initialReferenceId: incident.id,
                initialStream: AlertStream.monitoring,
              ),
            ),
          );
          return;
        }
      }
    }

    _showMissingHomeAttention(item.type);
  }

  void _openHomeAlerts() {
    if (widget.homeRepository.isLiveData) {
      _showHomeDestinationNotice(
        'The Alerts screen remains demo-backed until M4.',
      );
      return;
    }
    _selectDestination(2);
  }

  void _openHomeTanks() {
    if (widget.homeRepository.isLiveData) {
      _showHomeDestinationNotice(
        'The Tanks screen remains demo-backed until M3.',
      );
      return;
    }
    _selectDestination(1);
  }

  void _showHomeDestinationNotice(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _showMissingHomeAttention(HomeAttentionType type) {
    _selectDestination(2);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            type == HomeAttentionType.monitoring
                ? 'This monitoring incident is no longer available.'
                : 'This alert is no longer available.',
          ),
        ),
      );
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
            child: LayoutBuilder(
              builder: (context, constraints) {
                final slotWidth = constraints.maxWidth / 4;
                final capsuleWidth = (slotWidth - 4).clamp(
                  0.0,
                  constraints.maxWidth,
                );
                final animationDuration =
                    MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 200);

                return Stack(
                  fit: StackFit.expand,
                  children: [
                    AnimatedPositioned(
                      key: const ValueKey(
                        'soft-floating-dock-selected-capsule',
                      ),
                      duration: animationDuration,
                      curve: Curves.easeOutCubic,
                      top: 2,
                      left: (selectedIndex * slotWidth) + 2,
                      width: capsuleWidth,
                      height: 54,
                      child: IgnorePointer(
                        child: ExcludeSemantics(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: AppColors.mint,
                              border: Border.all(
                                color: AppColors.teal.withValues(alpha: 0.14),
                              ),
                              borderRadius: BorderRadius.circular(17),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Row(
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
                  ],
                );
              },
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
      child: Semantics(
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
                child: SizedBox(
                  height: 54,
                  child: Column(
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
      ),
    );
  }
}

import 'package:aqualogic/features/control/models/control_device.dart';
import 'package:aqualogic/features/control/widgets/control_widgets.dart';
import 'package:aqualogic/features/sensors/models/sensor_snapshot.dart';
import 'package:aqualogic/shared/widgets/app_page.dart';
import 'package:aqualogic/shared/widgets/header_panel.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class ControlScreen extends StatefulWidget {
  const ControlScreen({super.key, required this.snapshot});

  final SensorSnapshot snapshot;

  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen> {
  late final List<ControlDevice> _devices = [
    const ControlDevice(
      icon: LucideIcons.lightbulb,
      title: 'LED Lighting',
      subtitle: 'Maintains daily light rhythm',
      schedule: '07:00 - 19:00',
      active: true,
      autoMode: true,
    ),
    const ControlDevice(
      icon: LucideIcons.utensils,
      title: 'Auto Feeder',
      subtitle: 'Runs small scheduled feed cycles',
      schedule: '08:00, 14:00, 20:00',
      active: true,
      autoMode: true,
    ),
    const ControlDevice(
      icon: LucideIcons.funnel,
      title: 'Filtration Pump',
      subtitle: 'Keeps water circulation stable',
      schedule: '24/7 with backwash at 03:00',
      active: true,
      autoMode: true,
    ),
    const ControlDevice(
      icon: LucideIcons.shieldCheck,
      title: 'UV Sterilizer',
      subtitle: 'Reduces algae and pathogens',
      schedule: 'Daily 02:00 - 02:45',
      active: false,
      autoMode: true,
    ),
    const ControlDevice(
      icon: LucideIcons.droplet,
      title: 'Water Replacement',
      subtitle: 'Partial water change routine',
      schedule: 'Weekly Sunday 04:00',
      active: false,
      autoMode: false,
    ),
    const ControlDevice(
      icon: LucideIcons.flaskConical,
      title: 'Chemical Dosing',
      subtitle: 'Demo response to pH deviation',
      schedule: 'When pH deviation > 0.3',
      active: true,
      autoMode: true,
    ),
  ];

  void _updateDevice(int index, ControlDevice device) {
    setState(() => _devices[index] = device);
  }

  Future<void> _setTimer(int index) async {
    final selected = await showModalBottomSheet<TimeOfDay>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const FriendlyTimePickerSheet(),
    );
    if (selected == null || !mounted) return;

    final formatted = selected.format(context);
    final device = _devices[index];
    _updateDevice(
      index,
      device.copyWith(
        schedule: 'Next run at $formatted',
        autoMode: true,
        lastAction: 'Timer set',
      ),
    );
  }

  void _showControlDetails(int index) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final device = _devices[index];
            void updateSheet(ControlDevice updated) {
              _updateDevice(index, updated);
              setSheetState(() {});
            }

            return ControlDetailSheet(
              device: device,
              onPowerChanged: (active) {
                updateSheet(
                  device.copyWith(
                    active: active,
                    lastAction: active ? 'Enabled locally' : 'Paused locally',
                  ),
                );
              },
              onAutoChanged: (autoMode) {
                updateSheet(
                  device.copyWith(
                    autoMode: autoMode,
                    lastAction: autoMode ? 'Auto mode on' : 'Manual mode on',
                  ),
                );
              },
              onSetTimer: () async {
                await _setTimer(index);
                if (mounted) setSheetState(() {});
              },
              onRunNow: () {
                _runNow(index);
                if (mounted) setSheetState(() {});
              },
            );
          },
        );
      },
    );
  }

  void _runNow(int index) {
    final device = _devices[index];
    _updateDevice(
      index,
      device.copyWith(active: true, lastAction: 'Manual run just now'),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${device.title} demo command queued'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppPage(
      header: const HeaderPanel(
        compact: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 8),
            Text(
              'Control panel',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              'One-tap overrides',
              style: TextStyle(color: Colors.white, fontSize: 12),
            ),
          ],
        ),
      ),
      children: [
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _devices.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.2,
          ),
          itemBuilder: (context, index) {
            final device = _devices[index];
            return ControlOverviewCard(
              device: device,
              onTap: () => _showControlDetails(index),
            );
          },
        ),
        const DemoNotice(),
      ],
    );
  }
}

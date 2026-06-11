import 'package:aqualogic/app/theme/app_colors.dart';
import 'package:aqualogic/features/fish/screens/fish_library_screen.dart';
import 'package:aqualogic/features/more/widgets/more_widgets.dart';
import 'package:aqualogic/features/sensors/models/sensor_snapshot.dart';
import 'package:aqualogic/shared/widgets/app_page.dart';
import 'package:aqualogic/shared/widgets/header_panel.dart';
import 'package:aqualogic/shared/widgets/soft_card.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class MoreScreen extends StatefulWidget {
  const MoreScreen({super.key, required this.snapshot});

  final SensorSnapshot snapshot;

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  var pushNotifications = true;
  var criticalOnlyAtNight = true;
  var hapticFeedback = false;

  @override
  Widget build(BuildContext context) {
    return AppPage(
      header: const HeaderPanel(
        compact: true,
        child: Align(
          alignment: Alignment.bottomLeft,
          child: Text(
            'More',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
      children: [
        const OwnerCard(),
        MoreTile(
          icon: LucideIcons.fish,
          title: 'Fish library',
          subtitle: 'Care references and species data',
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) => const FishLibraryScreen(),
              ),
            );
          },
        ),
        const MoreTile(
          icon: LucideIcons.chartLine,
          title: 'History & trends',
          subtitle: 'Sensor history over time',
        ),
        const MoreTile(
          icon: LucideIcons.panelTop,
          title: 'Web dashboard',
          subtitle: 'Deep analytics on desktop',
        ),
        SoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Preferences',
                style: TextStyle(
                  color: AppColors.text,
                  fontWeight: FontWeight.w800,
                ),
              ),
              PreferenceCheck(
                label: 'Push notifications',
                value: pushNotifications,
                onChanged: (value) {
                  setState(() => pushNotifications = value ?? false);
                },
              ),
              PreferenceCheck(
                label: 'Critical-only at night',
                value: criticalOnlyAtNight,
                onChanged: (value) {
                  setState(() => criticalOnlyAtNight = value ?? false);
                },
              ),
              PreferenceCheck(
                label: 'Haptic feedback',
                value: hapticFeedback,
                onChanged: (value) {
                  setState(() => hapticFeedback = value ?? false);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

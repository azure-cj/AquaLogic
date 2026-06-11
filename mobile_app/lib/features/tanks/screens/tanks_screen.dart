import 'package:aqualogic/features/demo/demo_data.dart';
import 'package:aqualogic/features/sensors/models/sensor_snapshot.dart';
import 'package:aqualogic/features/tanks/screens/tank_detail_screen.dart';
import 'package:aqualogic/features/tanks/widgets/tank_overview_card.dart';
import 'package:aqualogic/shared/widgets/app_page.dart';
import 'package:aqualogic/shared/widgets/header_panel.dart';
import 'package:aqualogic/shared/widgets/section_title.dart';
import 'package:flutter/material.dart';

class TanksScreen extends StatelessWidget {
  const TanksScreen({super.key, required this.snapshot});

  final SensorSnapshot snapshot;

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
              'Tanks',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              'Tap a tank for detailed monitoring',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      ),
      children: [
        const SectionTitle(title: 'Your tanks'),
        ...DemoData.tanks.map(
          (tank) => TankOverviewCard(
            tank: tank,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) =>
                      TankDetailScreen(tank: tank, snapshot: snapshot),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

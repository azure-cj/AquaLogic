import 'package:aqualogic/app/auth/auth_scope.dart';
import 'package:aqualogic/app/theme/app_colors.dart';
import 'package:aqualogic/features/auth/models/auth_user.dart';
import 'package:aqualogic/features/fish/screens/fish_library_screen.dart';
import 'package:aqualogic/features/more/screens/about_screen.dart';
import 'package:aqualogic/features/more/screens/account_screen.dart';
import 'package:aqualogic/features/more/screens/data_status_screen.dart';
import 'package:aqualogic/features/more/widgets/more_widgets.dart';
import 'package:aqualogic/features/sensors/models/sensor_snapshot.dart';
import 'package:aqualogic/shared/widgets/app_page.dart';
import 'package:aqualogic/shared/widgets/header_panel.dart';
import 'package:aqualogic/shared/widgets/semantic_status_widgets.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key, required this.snapshot, required this.user});

  final SensorSnapshot snapshot;
  final AuthUser user;

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
              'More',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
            SizedBox(height: 3),
            Text(
              'Account and useful resources',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      ),
      children: [
        const SectionHeader(title: 'Account'),
        AccountCard(
          user: user,
          onSignOut: () => AuthScope.of(context).signOut(),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) => AccountScreen(
                  user: user,
                  onSignOut: () => AuthScope.of(context).signOut(),
                ),
              ),
            );
          },
        ),
        const SectionHeader(title: 'Resources'),
        MoreTile(
          icon: LucideIcons.fish,
          title: 'Fish species',
          subtitle: 'Care references and suitability context',
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) => const FishLibraryScreen(),
              ),
            );
          },
        ),
        const SectionHeader(title: 'App & data'),
        MoreTile(
          icon: LucideIcons.refreshCw,
          title: 'Sync / local data',
          subtitle: 'See what this prototype is currently connected to',
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) => DataStatusScreen(snapshot: snapshot),
              ),
            );
          },
        ),
        MoreTile(
          icon: LucideIcons.info,
          title: 'About AquaLogic',
          subtitle: 'Product information and prototype boundary',
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) => const AboutScreen(),
              ),
            );
          },
        ),
        const SectionHeader(title: 'Session'),
        const _SessionNote(),
      ],
    );
  }
}

class _SessionNote extends StatelessWidget {
  const _SessionNote();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'Sign out is available from your account card above.',
      style: TextStyle(
        color: AppColors.muted,
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

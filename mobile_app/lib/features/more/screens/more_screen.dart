import 'package:aqualogic/app/auth/auth_scope.dart';
import 'package:aqualogic/app/theme/app_colors.dart';
import 'package:aqualogic/app/theme/app_tokens.dart';
import 'package:aqualogic/features/auth/models/auth_user.dart';
import 'package:aqualogic/features/fish/screens/fish_library_screen.dart';
import 'package:aqualogic/features/more/screens/about_screen.dart';
import 'package:aqualogic/features/more/screens/account_screen.dart';
import 'package:aqualogic/features/more/screens/data_status_screen.dart';
import 'package:aqualogic/features/more/widgets/more_header.dart';
import 'package:aqualogic/features/more/widgets/more_widgets.dart';
import 'package:aqualogic/features/sensors/models/sensor_snapshot.dart';
import 'package:aqualogic/shared/widgets/app_page.dart';
import 'package:aqualogic/shared/widgets/semantic_status_widgets.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key, required this.snapshot, required this.user});

  final SensorSnapshot snapshot;
  final AuthUser user;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: AppPage(
        bottomClearance: AppSpacing.bottomDockClearance,
        header: const MoreHeader(
          title: 'More',
          subtitle: 'Account, app settings, and resources',
          titleKey: ValueKey('more-page-title'),
        ),
        children: [
          const SectionHeader(title: 'Account'),
          AccountCard(
            user: user,
            onSignOut: () => AuthScope.of(context).signOut(),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => AccountScreen(
                    user: user,
                    onSignOut: () async {
                      await AuthScope.of(context).signOut();
                      if (context.mounted) {
                        Navigator.of(
                          context,
                        ).popUntil((route) => route.isFirst);
                      }
                    },
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
          MoreTileGroup(
            key: const ValueKey('more-app-data-group'),
            children: [
              MoreTile(
                icon: LucideIcons.refreshCw,
                title: 'Sync / local data',
                subtitle: 'Local data and connection status',
                grouped: true,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) =>
                          DataStatusScreen(snapshot: snapshot),
                    ),
                  );
                },
              ),
              MoreTile(
                icon: LucideIcons.info,
                title: 'About AquaLogic',
                subtitle: 'Product information and prototype scope',
                grouped: true,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => const AboutScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

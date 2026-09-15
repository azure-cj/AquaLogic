import 'package:aqualogic/app/theme/app_colors.dart';
import 'package:aqualogic/features/auth/models/auth_user.dart';
import 'package:aqualogic/shared/widgets/app_page.dart';
import 'package:aqualogic/shared/widgets/header_panel.dart';
import 'package:aqualogic/shared/widgets/semantic_status_widgets.dart';
import 'package:aqualogic/shared/widgets/soft_card.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key, required this.user, required this.onSignOut});

  final AuthUser user;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        top: false,
        child: AppPage(
          header: HeaderPanel(
            compact: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconButton.filledTonal(
                  tooltip: 'Back to More',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(LucideIcons.arrowLeft),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Account',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                const Text(
                  'Your local prototype identity',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          children: [
            SoftCard(
              child: Column(
                children: [
                  const CircleAvatar(
                    radius: 30,
                    backgroundColor: AppColors.headerTop,
                    child: Icon(
                      LucideIcons.user,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    user.name,
                    style: const TextStyle(
                      color: AppColors.text,
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    user.email,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 15),
                  InfoRow(
                    label: 'Role',
                    value: user.role.displayLabel,
                    icon: LucideIcons.badgeCheck,
                  ),
                  const Divider(height: 1),
                  const InfoRow(
                    label: 'Organization',
                    value: 'JRed Aquatics',
                    icon: LucideIcons.building2,
                  ),
                ],
              ),
            ),
            const SectionHeader(
              title: 'Session',
              subtitle:
                  'Authentication is local and memory-only in this prototype',
            ),
            const EmptyState(
              title: 'Local prototype session',
              message:
                  'Production sessions, secure storage, and backend account management are intentionally deferred.',
              icon: LucideIcons.shieldCheck,
            ),
            FilledButton.icon(
              key: const ValueKey('account-sign-out-button'),
              onPressed: onSignOut,
              icon: const Icon(LucideIcons.logOut),
              label: const Text('Sign out'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

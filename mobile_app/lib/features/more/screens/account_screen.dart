import 'package:aqualogic/app/theme/app_colors.dart';
import 'package:aqualogic/features/auth/models/auth_user.dart';
import 'package:aqualogic/features/more/widgets/more_header.dart';
import 'package:aqualogic/features/more/widgets/more_widgets.dart';
import 'package:aqualogic/shared/widgets/app_page.dart';
import 'package:flutter/material.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key, required this.user, required this.onSignOut});

  final AuthUser user;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        top: false,
        child: AppPage(
          header: MoreHeader(
            title: 'Account',
            subtitle: 'Your authenticated AquaLogic identity',
            titleKey: const ValueKey('account-page-title'),
            onBack: () => Navigator.of(context).pop(),
          ),
          children: [
            AccountCard(
              user: user,
              onSignOut: onSignOut,
              signOutKey: const ValueKey('account-sign-out-button'),
            ),
          ],
        ),
      ),
    );
  }
}

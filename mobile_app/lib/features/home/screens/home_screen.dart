import 'package:aqualogic/features/auth/models/auth_user.dart';
import 'package:aqualogic/features/auth/models/user_role.dart';
import 'package:aqualogic/features/home/data/mock_home_repository.dart';
import 'package:aqualogic/features/home/models/home_dashboard_data.dart';
import 'package:aqualogic/features/home/widgets/home_shared_widgets.dart';
import 'package:aqualogic/features/home/widgets/owner_home_content.dart';
import 'package:aqualogic/features/home/widgets/staff_home_content.dart';
import 'package:aqualogic/features/sensors/models/sensor_snapshot.dart';
import 'package:aqualogic/app/theme/app_tokens.dart';
import 'package:aqualogic/shared/widgets/app_page.dart';
import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.snapshot,
    required this.user,
    required this.onOpenAlerts,
    required this.onOpenTanks,
    this.onOpenAlert,
    this.repository = const MockHomeRepository(),
  });

  final SensorSnapshot snapshot;
  final AuthUser user;
  final VoidCallback onOpenAlerts;
  final VoidCallback onOpenTanks;
  final ValueChanged<HomeAttentionItem>? onOpenAlert;
  final HomeRepository repository;

  @override
  Widget build(BuildContext context) {
    final data = repository.load(snapshot: snapshot);
    final content = switch (user.role) {
      UserRole.admin => OwnerHomeContent(
        data: data,
        onOpenAlerts: onOpenAlerts,
        onOpenTanks: onOpenTanks,
        onOpenAlert: onOpenAlert,
      ),
      UserRole.staff => StaffHomeContent(
        data: data,
        onOpenAlerts: onOpenAlerts,
        onOpenTanks: onOpenTanks,
      ),
    };

    return AppPage(
      bottomClearance: AppSpacing.bottomDockClearance,
      header: HomeHero(
        user: user,
        isOnline: snapshot.isOnline,
        data: data,
        showFleetStatus: user.role == UserRole.admin,
      ),
      children: [content],
    );
  }
}

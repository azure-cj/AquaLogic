import 'package:aqualogic/features/auth/models/auth_user.dart';
import 'package:aqualogic/features/auth/models/user_role.dart';
import 'package:aqualogic/features/home/data/mock_home_repository.dart';
import 'package:aqualogic/features/home/widgets/home_shared_widgets.dart';
import 'package:aqualogic/features/home/widgets/owner_home_content.dart';
import 'package:aqualogic/features/home/widgets/staff_home_content.dart';
import 'package:aqualogic/features/sensors/models/sensor_snapshot.dart';
import 'package:aqualogic/shared/widgets/app_page.dart';
import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.snapshot,
    required this.user,
    required this.onOpenAlerts,
    required this.onOpenTanks,
    this.repository = const MockHomeRepository(),
  });

  final SensorSnapshot snapshot;
  final AuthUser user;
  final VoidCallback onOpenAlerts;
  final VoidCallback onOpenTanks;
  final HomeRepository repository;

  @override
  Widget build(BuildContext context) {
    final data = repository.load(snapshot: snapshot);
    final content = switch (user.role) {
      UserRole.admin => OwnerHomeContent(
        data: data,
        onOpenAlerts: onOpenAlerts,
        onOpenTanks: onOpenTanks,
      ),
      UserRole.staff => StaffHomeContent(
        data: data,
        onOpenAlerts: onOpenAlerts,
        onOpenTanks: onOpenTanks,
      ),
    };

    return AppPage(
      header: user.role == UserRole.admin
          ? OwnerHomeHero(user: user, isOnline: snapshot.isOnline, data: data)
          : RoleHomeHeader(user: user, isOnline: snapshot.isOnline),
      children: [content],
    );
  }
}

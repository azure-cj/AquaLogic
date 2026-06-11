import 'package:aqualogic/app/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class ConnectionBell extends StatelessWidget {
  const ConnectionBell({super.key, required this.isOnline});

  final bool isOnline;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        CircleAvatar(
          radius: 19,
          backgroundColor: Colors.white.withValues(alpha: 0.16),
          child: Icon(
            isOnline ? LucideIcons.bell : LucideIcons.wifiOff,
            color: Colors.white,
            size: 20,
          ),
        ),
        Positioned(
          right: 3,
          top: 4,
          child: CircleAvatar(
            radius: 4,
            backgroundColor: isOnline ? AppColors.success : AppColors.critical,
          ),
        ),
      ],
    );
  }
}

import 'package:aqualogic/app/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class ConnectionBell extends StatelessWidget {
  const ConnectionBell({super.key, required this.isOnline, this.light = false});

  /// Null means the AquaLogic API connection has not been checked yet.
  final bool? isOnline;
  final bool light;

  @override
  Widget build(BuildContext context) {
    final icon = isOnline == false ? LucideIcons.wifiOff : LucideIcons.bell;
    final statusColor = isOnline == true
        ? AppColors.success
        : isOnline == false
        ? AppColors.critical
        : AppColors.muted;
    return Semantics(
      label: switch (isOnline) {
        true => 'AquaLogic API reachable',
        false => 'AquaLogic connection unavailable',
        null => 'AquaLogic connection status unknown',
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: light
                ? Colors.white.withValues(alpha: 0.72)
                : Colors.white.withValues(alpha: 0.16),
            child: Icon(
              icon,
              color: light ? AppColors.tealDark : Colors.white,
              size: 20,
            ),
          ),
          Positioned(
            right: 3,
            top: 4,
            child: CircleAvatar(radius: 4, backgroundColor: statusColor),
          ),
        ],
      ),
    );
  }
}

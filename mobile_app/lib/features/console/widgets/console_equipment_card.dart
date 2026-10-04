import 'package:flutter/material.dart';
import 'console_style.dart';

class ConsoleEquipmentCard extends StatelessWidget {
  const ConsoleEquipmentCard({
    super.key,
    required this.label,
    required this.status,
    required this.icon,
    required this.onTap,
    this.readOnly = false,
  });
  final String label;
  final String status;
  final IconData icon;
  final VoidCallback? onTap;
  final bool readOnly;

  @override
  Widget build(BuildContext context) => Material(
    color: ConsoleStyle.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: ConsoleStyle.border),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 24,
              color: onTap == null || readOnly
                  ? ConsoleStyle.muted
                  : ConsoleStyle.accent,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              style: const TextStyle(
                fontSize: 16,
                height: 1,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '$status${readOnly ? ' · READ ONLY' : ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                height: 1,
                fontWeight: FontWeight.w600,
                color: readOnly || onTap == null
                    ? ConsoleStyle.muted
                    : ConsoleStyle.good,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

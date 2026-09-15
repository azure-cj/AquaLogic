import 'package:aqualogic/app/theme/app_colors.dart';
import 'package:aqualogic/features/auth/models/auth_user.dart';
import 'package:aqualogic/shared/widgets/soft_card.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class AccountCard extends StatelessWidget {
  const AccountCard({
    super.key,
    required this.user,
    required this.onSignOut,
    this.onTap,
  });

  final AuthUser user;
  final VoidCallback onSignOut;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = SoftCard(
      child: Column(
        children: [
          Row(
            children: [
              const CircleAvatar(
                radius: 23,
                backgroundColor: AppColors.headerTop,
                child: Icon(LucideIcons.user, color: Colors.white),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      user.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              _RoleBadge(label: user.role.displayLabel),
              if (onTap != null) ...[
                const SizedBox(width: 4),
                const Icon(
                  LucideIcons.chevronRight,
                  color: AppColors.muted,
                  size: 18,
                ),
              ],
            ],
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              const Icon(
                LucideIcons.building2,
                color: AppColors.tealDark,
                size: 15,
              ),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'JRed Aquatics · Local prototype account',
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton(
                key: const ValueKey('sign-out-button'),
                onPressed: onSignOut,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.tealDark,
                  minimumSize: const Size(44, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                ),
                child: const Text('Sign out'),
              ),
            ],
          ),
        ],
      ),
    );

    if (onTap == null) return content;
    return Semantics(
      button: true,
      label: 'Open account for ${user.name}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: content,
        ),
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.mint,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          color: AppColors.tealDark,
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class MoreTile extends StatelessWidget {
  const MoreTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      label: onTap == null ? title : 'Open $title',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Ink(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.line),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: AppColors.teal.withValues(alpha: 0.18),
                  child: Icon(icon, color: AppColors.tealDark),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: AppColors.text,
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 11,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onTap != null)
                  const Icon(LucideIcons.chevronRight, color: AppColors.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

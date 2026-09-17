import 'package:aqualogic/app/theme/app_colors.dart';
import 'package:aqualogic/features/auth/models/auth_user.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class AccountCard extends StatelessWidget {
  const AccountCard({
    super.key,
    required this.user,
    required this.onSignOut,
    this.onTap,
    this.signOutKey,
  });

  final AuthUser user;
  final VoidCallback onSignOut;
  final VoidCallback? onTap;
  final Key? signOutKey;

  @override
  Widget build(BuildContext context) {
    final panel = Material(
      type: MaterialType.transparency,
      child: Ink(
        key: const ValueKey('account-profile-panel'),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.line),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          excludeFromSemantics: true,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(15, 15, 15, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  button: onTap != null,
                  onTap: onTap,
                  label: onTap == null
                      ? null
                      : 'Open account for ${user.name}. ${user.email}. '
                            '${user.role.badgeLabel}',
                  excludeSemantics: onTap != null,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const ExcludeSemantics(
                        child: CircleAvatar(
                          radius: 23,
                          backgroundColor: AppColors.headerTop,
                          child: Icon(LucideIcons.user, color: Colors.white),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user.name,
                              style: const TextStyle(
                                color: AppColors.text,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                height: 1.15,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              user.email,
                              style: const TextStyle(
                                color: AppColors.muted,
                                fontSize: 11,
                                height: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      _RoleBadge(label: user.role.badgeLabel),
                      if (onTap != null) ...[
                        const SizedBox(width: 3),
                        const ExcludeSemantics(
                          child: Icon(
                            LucideIcons.chevronRight,
                            color: AppColors.muted,
                            size: 18,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 11),
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 58),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'JRed Aquatics',
                        style: TextStyle(
                          color: AppColors.text,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      const Text(
                        'Local prototype account',
                        style: TextStyle(
                          color: AppColors.muted,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w400,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Semantics(
                    container: true,
                    button: true,
                    label: 'Sign out',
                    excludeSemantics: true,
                    child: TextButton(
                      key: signOutKey ?? const ValueKey('sign-out-button'),
                      onPressed: onSignOut,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.tealDark,
                        minimumSize: const Size(44, 44),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        tapTargetSize: MaterialTapTargetSize.padded,
                      ),
                      child: const Text(
                        'Sign out',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return panel;
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
        border: Border.all(color: AppColors.teal.withValues(alpha: 0.24)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          color: AppColors.tealDark,
          fontSize: 10,
          fontWeight: FontWeight.w700,
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
    this.grouped = false,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool grouped;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tile = Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.teal.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.tealDark, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 11,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 8),
            const ExcludeSemantics(
              child: Icon(
                LucideIcons.chevronRight,
                color: AppColors.muted,
                size: 19,
              ),
            ),
          ],
        ],
      ),
    );

    final semanticsLabel = onTap == null
        ? '$title. $subtitle'
        : 'Open $title. $subtitle';
    final interactiveTile = Semantics(
      container: true,
      button: onTap != null,
      label: semanticsLabel,
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(onTap: onTap, child: tile),
      ),
    );

    if (grouped) return interactiveTile;

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.line),
        ),
        child: interactiveTile,
      ),
    );
  }
}

class MoreTileGroup extends StatelessWidget {
  const MoreTileGroup({super.key, required this.children});

  final List<MoreTile> children;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          children: [
            for (var index = 0; index < children.length; index++) ...[
              children[index],
              if (index < children.length - 1)
                Divider(
                  height: 1,
                  thickness: 1,
                  indent: 64,
                  endIndent: 12,
                  color: AppColors.line.withValues(alpha: 0.82),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

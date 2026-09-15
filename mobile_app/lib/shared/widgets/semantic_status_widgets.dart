import 'package:aqualogic/app/theme/app_colors.dart';
import 'package:aqualogic/shared/models/aqualogic_status.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class OperationalStatusBadge extends StatelessWidget {
  const OperationalStatusBadge({
    super.key,
    required this.status,
    this.label,
    this.compact = false,
  });

  final OperationalStatus status;
  final String? label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = _operationalColor(status);
    return _SemanticBadge(
      label: label ?? status.label,
      color: color,
      icon: _operationalIcon(status),
      compact: compact,
      semanticsLabel: 'Tank status ${label ?? status.label}',
    );
  }
}

class LifecycleBadge extends StatelessWidget {
  const LifecycleBadge({
    super.key,
    this.label = 'Retired',
    this.compact = false,
  });

  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return _SemanticBadge(
      label: label,
      color: AppColors.muted,
      icon: LucideIcons.archive,
      compact: compact,
      semanticsLabel: 'Tank lifecycle $label',
    );
  }
}

class SpeciesSuitabilityBadge extends StatelessWidget {
  const SpeciesSuitabilityBadge({
    super.key,
    required this.suitability,
    this.compact = false,
  });

  final SpeciesSuitability suitability;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = _suitabilityColor(suitability);
    return _SemanticBadge(
      label: suitability.label,
      color: color,
      icon: _suitabilityIcon(suitability),
      compact: compact,
      semanticsLabel: 'Species suitability ${suitability.label}',
    );
  }
}

class DeviceConnectionBadge extends StatelessWidget {
  const DeviceConnectionBadge({
    super.key,
    required this.status,
    this.compact = false,
  });

  final DeviceConnectionStatus status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = _connectionColor(status);
    return _SemanticBadge(
      label: status.label,
      color: color,
      icon: _connectionIcon(status),
      compact: compact,
      semanticsLabel: 'Equipment connection ${status.label}',
    );
  }
}

class CommandStatusBadge extends StatelessWidget {
  const CommandStatusBadge({
    super.key,
    required this.status,
    this.compact = false,
  });

  final CommandStatus status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = _commandColor(status);
    return _SemanticBadge(
      label: status.label,
      color: color,
      icon: _commandIcon(status),
      compact: compact,
      semanticsLabel: 'Command status ${status.label}',
    );
  }
}

class FreshnessLabel extends StatelessWidget {
  const FreshnessLabel({
    super.key,
    required this.label,
    this.isUnavailable = false,
  });

  final String label;
  final bool isUnavailable;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Data freshness $label',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isUnavailable ? LucideIcons.wifiOff : LucideIcons.clock3,
            size: 14,
            color: isUnavailable ? AppColors.offline : AppColors.muted,
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isUnavailable ? AppColors.offline : AppColors.muted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.text,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle!,
                  style: const TextStyle(color: AppColors.muted, fontSize: 11),
                ),
              ],
            ],
          ),
        ),
        if (actionLabel != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              minimumSize: const Size(44, 44),
              padding: const EdgeInsets.symmetric(horizontal: 6),
            ),
            child: Text(actionLabel!),
          ),
      ],
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    required this.message,
    this.icon = LucideIcons.circleCheck,
  });

  final String title;
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 21,
            backgroundColor: AppColors.mint,
            child: Icon(icon, color: AppColors.tealDark),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class InfoRow extends StatelessWidget {
  const InfoRow({
    super.key,
    required this.label,
    required this.value,
    this.icon,
  });

  final String label;
  final String value;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 17, color: AppColors.tealDark),
            const SizedBox(width: 9),
          ],
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(
                color: AppColors.text,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SemanticBadge extends StatelessWidget {
  const _SemanticBadge({
    required this.label,
    required this.color,
    required this.icon,
    required this.semanticsLabel,
    required this.compact,
  });

  final String label;
  final Color color;
  final IconData icon;
  final String semanticsLabel;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: semanticsLabel,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 7 : 9,
          vertical: compact ? 4 : 5,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          border: Border.all(color: color.withValues(alpha: 0.7)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: compact ? 12 : 14),
            const SizedBox(width: 5),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: compact ? 9 : 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Color _operationalColor(OperationalStatus status) {
  return switch (status) {
    OperationalStatus.normal => AppColors.success,
    OperationalStatus.warning => AppColors.warning,
    OperationalStatus.critical => AppColors.critical,
    OperationalStatus.offline => AppColors.offline,
  };
}

IconData _operationalIcon(OperationalStatus status) {
  return switch (status) {
    OperationalStatus.normal => LucideIcons.circleCheck,
    OperationalStatus.warning => LucideIcons.triangleAlert,
    OperationalStatus.critical => LucideIcons.circleAlert,
    OperationalStatus.offline => LucideIcons.wifiOff,
  };
}

Color _suitabilityColor(SpeciesSuitability suitability) {
  return switch (suitability) {
    SpeciesSuitability.suitable => AppColors.tealDark,
    SpeciesSuitability.attention => AppColors.warning,
    SpeciesSuitability.unavailable => AppColors.offline,
  };
}

IconData _suitabilityIcon(SpeciesSuitability suitability) {
  return switch (suitability) {
    SpeciesSuitability.suitable => LucideIcons.circleCheck,
    SpeciesSuitability.attention => LucideIcons.triangleAlert,
    SpeciesSuitability.unavailable => LucideIcons.circleHelp,
  };
}

Color _connectionColor(DeviceConnectionStatus status) {
  return switch (status) {
    DeviceConnectionStatus.online => AppColors.success,
    DeviceConnectionStatus.offline => AppColors.offline,
    DeviceConnectionStatus.unknown => AppColors.muted,
  };
}

IconData _connectionIcon(DeviceConnectionStatus status) {
  return switch (status) {
    DeviceConnectionStatus.online => LucideIcons.wifi,
    DeviceConnectionStatus.offline => LucideIcons.wifiOff,
    DeviceConnectionStatus.unknown => LucideIcons.circleHelp,
  };
}

Color _commandColor(CommandStatus status) {
  return switch (status) {
    CommandStatus.queued || CommandStatus.executing => AppColors.tealDark,
    CommandStatus.succeeded => AppColors.success,
    CommandStatus.failed => AppColors.critical,
    CommandStatus.expired => AppColors.warning,
    CommandStatus.outcomeUnknown => AppColors.offline,
  };
}

IconData _commandIcon(CommandStatus status) {
  return switch (status) {
    CommandStatus.queued => LucideIcons.clock3,
    CommandStatus.executing => LucideIcons.loaderCircle,
    CommandStatus.succeeded => LucideIcons.circleCheck,
    CommandStatus.failed => LucideIcons.circleX,
    CommandStatus.expired => LucideIcons.timerOff,
    CommandStatus.outcomeUnknown => LucideIcons.circleHelp,
  };
}

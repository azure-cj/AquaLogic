import 'package:aqualogic/app/theme/app_colors.dart';
import 'package:aqualogic/features/sensors/models/sensor_snapshot.dart';
import 'package:aqualogic/features/tanks/models/tank_info.dart';
import 'package:aqualogic/shared/widgets/soft_card.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class ReadingGrid extends StatelessWidget {
  const ReadingGrid({super.key, required this.snapshot, this.readings});

  final SensorSnapshot snapshot;
  final List<TankReading>? readings;

  List<TankReading> get _items {
    if (readings != null) return readings!;
    final unavailable = !snapshot.isOnline;
    return [
      TankReading(
        parameter: SensorParameter.temperature,
        value: unavailable ? '—' : snapshot.temperatureC.toStringAsFixed(1),
        unit: '°C',
        condition: unavailable
            ? ReadingCondition.unavailable
            : _condition(snapshot.tempStatus),
        timestampLabel: unavailable ? 'No recent report' : 'Just now',
      ),
      TankReading(
        parameter: SensorParameter.ph,
        value: unavailable ? '—' : snapshot.ph.toStringAsFixed(1),
        unit: 'pH',
        condition: unavailable
            ? ReadingCondition.unavailable
            : _condition(snapshot.phStatus),
        timestampLabel: unavailable ? 'No recent report' : 'Just now',
      ),
      TankReading(
        parameter: SensorParameter.turbidity,
        value: unavailable ? '—' : snapshot.turbidityRaw.toString(),
        unit: 'raw',
        condition: unavailable
            ? ReadingCondition.unavailable
            : _condition(snapshot.turbidityStatus),
        timestampLabel: unavailable ? 'No recent report' : 'Just now',
      ),
      TankReading(
        parameter: SensorParameter.tds,
        value: unavailable ? '—' : snapshot.tdsRaw.toString(),
        unit: 'ppm',
        condition: unavailable
            ? ReadingCondition.unavailable
            : _condition(snapshot.tdsStatus),
        timestampLabel: unavailable ? 'No recent report' : 'Just now',
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 10.0;
        final columns = constraints.maxWidth >= 340 ? 2 : 1;
        final width = columns == 2
            ? (constraints.maxWidth - spacing) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final reading in _items)
              SizedBox(
                width: width,
                child: ReadingCard(reading: reading),
              ),
          ],
        );
      },
    );
  }
}

class ReadingCardData {
  const ReadingCardData({
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
    required this.status,
    required this.note,
    required this.trend,
  });

  final IconData icon;
  final String label;
  final String value;
  final String unit;
  final String status;
  final String note;
  final String trend;
}

class ReadingCard extends StatelessWidget {
  const ReadingCard({super.key, required this.reading});

  final TankReading reading;

  @override
  Widget build(BuildContext context) {
    final color = _conditionColor(reading.condition);
    return Semantics(
      container: true,
      label:
          '${reading.parameter.label} ${reading.value} ${reading.unit}, '
          '${reading.condition.label}',
      child: SoftCard(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 17,
                  backgroundColor: AppColors.teal.withValues(alpha: 0.18),
                  child: Icon(
                    _parameterIcon(reading.parameter),
                    color: AppColors.tealDark,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    reading.parameter.label,
                    style: const TextStyle(
                      color: AppColors.text,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                _ConditionBadge(condition: reading.condition),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Flexible(
                  child: Text(
                    reading.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: reading.isAvailable
                          ? AppColors.text
                          : AppColors.offline,
                      fontSize: 27,
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
                  ),
                ),
                const SizedBox(width: 5),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    reading.unit,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            Text(
              reading.note ?? reading.timestampLabel,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: reading.isAvailable
                    ? AppColors.muted
                    : AppColors.offline,
                fontSize: 10,
                height: 1.3,
                fontWeight: reading.isAvailable
                    ? FontWeight.w500
                    : FontWeight.w700,
              ),
            ),
            if (reading.note != null) ...[
              const SizedBox(height: 3),
              Text(
                reading.timestampLabel,
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Container(
              height: 3,
              width: double.infinity,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.28),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConditionBadge extends StatelessWidget {
  const _ConditionBadge({required this.condition});

  final ReadingCondition condition;

  @override
  Widget build(BuildContext context) {
    final color = _conditionColor(condition);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color.withValues(alpha: 0.7)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_conditionIcon(condition), color: color, size: 11),
          const SizedBox(width: 4),
          Text(
            condition.label,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

ReadingCondition _condition(String status) {
  return switch (status.trim().toUpperCase()) {
    'NORMAL' || 'CLEAR' => ReadingCondition.normal,
    'LOW' || 'HIGH' || 'MODERATE' => ReadingCondition.warning,
    'CRITICAL' || 'DIRTY' => ReadingCondition.critical,
    _ => ReadingCondition.unavailable,
  };
}

Color _conditionColor(ReadingCondition condition) {
  return switch (condition) {
    ReadingCondition.normal => AppColors.success,
    ReadingCondition.warning => AppColors.warning,
    ReadingCondition.critical => AppColors.critical,
    ReadingCondition.unavailable => AppColors.offline,
  };
}

IconData _conditionIcon(ReadingCondition condition) {
  return switch (condition) {
    ReadingCondition.normal => LucideIcons.circleCheck,
    ReadingCondition.warning => LucideIcons.triangleAlert,
    ReadingCondition.critical => LucideIcons.circleAlert,
    ReadingCondition.unavailable => LucideIcons.circleHelp,
  };
}

IconData _parameterIcon(SensorParameter parameter) {
  return switch (parameter) {
    SensorParameter.temperature => LucideIcons.thermometer,
    SensorParameter.ph => LucideIcons.testTube,
    SensorParameter.turbidity => LucideIcons.droplets,
    SensorParameter.tds => LucideIcons.zap,
  };
}

import 'package:aqualogic/app/theme/app_colors.dart';
import 'package:aqualogic/features/sensors/models/sensor_snapshot.dart';
import 'package:aqualogic/features/tanks/models/tank_info.dart';
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
    final items = _items;
    if (items.isEmpty) {
      return _ReadingSurface(
        child: const Text(
          'No sensor readings are available.',
          style: TextStyle(color: AppColors.muted, fontSize: 12),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= 340 && items.length > 1;
        return _ReadingSurface(
          child: twoColumns
              ? _TwoColumnReadingGrid(items: items)
              : _SingleColumnReadingGrid(items: items),
        );
      },
    );
  }
}

class _ReadingSurface extends StatelessWidget {
  const _ReadingSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('sensor-overview-panel'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(18),
      ),
      child: child,
    );
  }
}

class _TwoColumnReadingGrid extends StatelessWidget {
  const _TwoColumnReadingGrid({required this.items});

  final List<TankReading> items;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var index = 0; index < items.length; index += 2) {
      if (index > 0) {
        rows.add(const Divider(height: 1, thickness: 1, color: AppColors.line));
      }
      final right = index + 1 < items.length ? items[index + 1] : null;
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _SensorReadingCell(reading: items[index])),
              const VerticalDivider(
                width: 1,
                thickness: 1,
                color: AppColors.line,
              ),
              Expanded(
                child: right == null
                    ? const SizedBox.shrink()
                    : _SensorReadingCell(reading: right),
              ),
            ],
          ),
        ),
      );
    }
    return Column(children: rows);
  }
}

class _SingleColumnReadingGrid extends StatelessWidget {
  const _SingleColumnReadingGrid({required this.items});

  final List<TankReading> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var index = 0; index < items.length; index++) ...[
          _SensorReadingCell(reading: items[index]),
          if (index < items.length - 1)
            const Divider(height: 1, thickness: 1, color: AppColors.line),
        ],
      ],
    );
  }
}

class ReadingCard extends StatelessWidget {
  const ReadingCard({super.key, required this.reading});

  final TankReading reading;

  @override
  Widget build(BuildContext context) {
    return _SensorReadingCell(reading: reading);
  }
}

class _SensorReadingCell extends StatelessWidget {
  const _SensorReadingCell({required this.reading});

  final TankReading reading;

  @override
  Widget build(BuildContext context) {
    final valueColor = reading.isAvailable ? AppColors.text : AppColors.offline;
    return Semantics(
      container: true,
      label:
          '${reading.parameter.label}, ${reading.value} ${reading.unit}, '
          '${reading.condition.label}, ${reading.timestampLabel}',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 10, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.teal.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _parameterIcon(reading.parameter),
                    color: AppColors.tealDark,
                    size: 17,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          reading.parameter.label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.text,
                            fontSize: 12.5,
                            height: 1.15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        _ReadingStatus(condition: reading.condition),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _ReadingValue(reading: reading, valueColor: valueColor),
            const SizedBox(height: 7),
            Text(
              reading.timestampLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: reading.isAvailable
                    ? AppColors.muted
                    : AppColors.offline,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadingValue extends StatelessWidget {
  const _ReadingValue({required this.reading, required this.valueColor});

  final TankReading reading;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    final stackUnit =
        MediaQuery.sizeOf(context).width < 360 ||
        MediaQuery.textScalerOf(context).scale(1) > 1.25;
    final value = FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(
        reading.value,
        softWrap: false,
        style: TextStyle(
          color: valueColor,
          fontSize: 29,
          height: 0.98,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    final unit = Text(
      reading.unit,
      softWrap: false,
      style: const TextStyle(
        color: AppColors.muted,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
    );

    if (stackUnit) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: double.infinity, child: value),
          Padding(padding: const EdgeInsets.only(top: 1), child: unit),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: value),
        const SizedBox(width: 5),
        Padding(padding: const EdgeInsets.only(bottom: 2), child: unit),
      ],
    );
  }
}

class _ReadingStatus extends StatelessWidget {
  const _ReadingStatus({required this.condition});

  final ReadingCondition condition;

  @override
  Widget build(BuildContext context) {
    final color = _conditionColor(condition);
    final quietColor = condition == ReadingCondition.normal
        ? color.withValues(alpha: 0.78)
        : color;
    final icon = _conditionIcon(condition);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: quietColor, size: 11),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            condition.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: quietColor,
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
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

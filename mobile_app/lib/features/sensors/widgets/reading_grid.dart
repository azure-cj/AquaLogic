import 'package:aqualogic/app/theme/app_colors.dart';
import 'package:aqualogic/features/sensors/models/sensor_snapshot.dart';
import 'package:aqualogic/shared/models/reading_state.dart';
import 'package:aqualogic/shared/widgets/soft_card.dart';
import 'package:aqualogic/shared/widgets/status_pill.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class ReadingGrid extends StatelessWidget {
  const ReadingGrid({super.key, required this.snapshot});

  final SensorSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final readings = [
      ReadingCardData(
        icon: LucideIcons.thermometer,
        label: 'Temperature',
        value: snapshot.temperatureC.toStringAsFixed(1),
        unit: '°C',
        status: snapshot.tempStatus,
        note: 'Optimal for tropical species',
        trend: '+0.2',
      ),
      ReadingCardData(
        icon: LucideIcons.testTube,
        label: 'pH Level',
        value: snapshot.ph.toStringAsFixed(1),
        unit: 'pH',
        status: snapshot.phStatus,
        note: 'Freshwater target 6.5-8.0',
        trend: '+0.1',
      ),
      ReadingCardData(
        icon: LucideIcons.droplet,
        label: 'Turbidity',
        value: snapshot.turbidityRaw.toString(),
        unit: 'raw',
        status: snapshot.turbidityStatus,
        note: 'Clear water target > 2500',
        trend: '-0.2',
      ),
      ReadingCardData(
        icon: LucideIcons.zap,
        label: 'TDS',
        value: snapshot.tdsRaw.toString(),
        unit: 'ppm',
        status: snapshot.tdsStatus,
        note: 'Mineral content nominal',
        trend: '+8',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 12.0;
        final itemWidth = (constraints.maxWidth - spacing) / 2;
        final itemHeight = itemWidth / 1.02;

        return Column(
          children: [
            for (var row = 0; row < readings.length; row += 2) ...[
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: itemHeight,
                      child: ReadingCard(data: readings[row]),
                    ),
                  ),
                  const SizedBox(width: spacing),
                  Expanded(
                    child: SizedBox(
                      height: itemHeight,
                      child: ReadingCard(data: readings[row + 1]),
                    ),
                  ),
                ],
              ),
              if (row + 2 < readings.length) const SizedBox(height: spacing),
            ],
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

  ReadingState get state {
    if (status == 'NORMAL' || status == 'CLEAR') return ReadingState.normal;
    if (status == 'DIRTY' || status == 'CRITICAL' || status == 'NO SENSOR') {
      return ReadingState.critical;
    }
    return ReadingState.warning;
  }
}

class ReadingCard extends StatelessWidget {
  const ReadingCard({super.key, required this.data});

  final ReadingCardData data;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.teal.withValues(alpha: 0.18),
                child: Icon(data.icon, color: AppColors.tealDark, size: 19),
              ),
              const Spacer(),
              StatusPill(label: data.status, state: data.state),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            data.label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const Spacer(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: Text(
                  data.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 25,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  data.unit,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: switch (data.state) {
                ReadingState.normal => 0.72,
                ReadingState.warning => 0.48,
                ReadingState.critical => 0.18,
              },
              minHeight: 6,
              backgroundColor: AppColors.line.withValues(alpha: 0.62),
              valueColor: AlwaysStoppedAnimation<Color>(stateColor(data.state)),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  data.note,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.muted, fontSize: 10),
                ),
              ),
              Text(
                data.trend,
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

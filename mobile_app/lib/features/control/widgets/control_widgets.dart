import 'package:aqualogic/app/theme/app_colors.dart';
import 'package:aqualogic/features/control/models/control_device.dart';
import 'package:aqualogic/shared/widgets/soft_card.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class ControlOverviewCard extends StatelessWidget {
  const ControlOverviewCard({
    super.key,
    required this.device,
    required this.onTap,
  });

  final ControlDevice device;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: device.active
                ? AppColors.teal.withValues(alpha: 0.72)
                : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: device.active ? Colors.transparent : AppColors.line,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.tealDark.withValues(alpha: 0.10),
                blurRadius: 14,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(device.icon, color: AppColors.text, size: 27),
              const Spacer(),
              Text(
                device.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.text,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                device.schedule,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: device.active
                      ? AppColors.text.withValues(alpha: 0.68)
                      : AppColors.muted,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Container(
                width: device.active ? 34 : 24,
                height: 6,
                decoration: BoxDecoration(
                  color: device.active ? AppColors.tealDark : AppColors.line,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ControlDetailSheet extends StatelessWidget {
  const ControlDetailSheet({
    super.key,
    required this.device,
    required this.onPowerChanged,
    required this.onAutoChanged,
    required this.onSetTimer,
    required this.onRunNow,
  });

  final ControlDevice device;
  final ValueChanged<bool> onPowerChanged;
  final ValueChanged<bool> onAutoChanged;
  final VoidCallback onSetTimer;
  final VoidCallback onRunNow;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 5,
                decoration: BoxDecoration(
                  color: AppColors.line,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: AppColors.teal.withValues(alpha: 0.20),
                  child: Icon(device.icon, color: AppColors.tealDark),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        device.title,
                        style: const TextStyle(
                          color: AppColors.text,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        device.subtitle,
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(LucideIcons.x),
                ),
              ],
            ),
            const SizedBox(height: 18),
            SoftCard(
              child: Column(
                children: [
                  DetailSwitchRow(
                    title: 'Device active',
                    subtitle: device.active ? 'Demo output enabled' : 'Paused',
                    value: device.active,
                    onChanged: onPowerChanged,
                  ),
                  const Divider(height: 22),
                  DetailSwitchRow(
                    title: 'Automatic mode',
                    subtitle: device.autoMode
                        ? 'Runs from schedule'
                        : 'Manual commands only',
                    value: device.autoMode,
                    onChanged: onAutoChanged,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SoftCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Schedule',
                    style: TextStyle(
                      color: AppColors.text,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    device.schedule,
                    style: const TextStyle(
                      color: AppColors.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: onSetTimer,
                      icon: const Icon(LucideIcons.clock),
                      label: const Text('Set next run'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onRunNow,
                    icon: const Icon(LucideIcons.play),
                    label: const Text('Run now'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () => onPowerChanged(false),
                    icon: const Icon(LucideIcons.octagonX),
                    label: const Text('Stop'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Last action: ${device.lastAction}',
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DetailSwitchRow extends StatelessWidget {
  const DetailSwitchRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
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
              Text(
                subtitle,
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ],
          ),
        ),
        Switch.adaptive(
          value: value,
          activeThumbColor: AppColors.text,
          activeTrackColor: AppColors.teal.withValues(alpha: 0.45),
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class FriendlyTimePickerSheet extends StatefulWidget {
  const FriendlyTimePickerSheet({super.key});

  @override
  State<FriendlyTimePickerSheet> createState() =>
      _FriendlyTimePickerSheetState();
}

class _FriendlyTimePickerSheetState extends State<FriendlyTimePickerSheet> {
  late var hour = TimeOfDay.now().hour;
  late var minute = _roundedMinute(TimeOfDay.now().minute);

  static int _roundedMinute(int value) => ((value / 5).round() * 5) % 60;

  String get label =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  void adjustHour(int delta) {
    setState(() {
      hour = (hour + delta) % 24;
      if (hour < 0) hour = 23;
    });
  }

  void adjustMinute(int delta) {
    setState(() {
      final next = minute + delta;
      if (next >= 60) {
        minute = 0;
        hour = (hour + 1) % 24;
      } else if (next < 0) {
        minute = 55;
        hour = (hour - 1) % 24;
        if (hour < 0) hour = 23;
      } else {
        minute = next;
      }
    });
  }

  void setPreset(int presetHour) {
    setState(() {
      if (presetHour == -1) {
        final now = TimeOfDay.now();
        hour = (now.hour + 1) % 24;
        minute = 0;
      } else {
        hour = presetHour;
        minute = 0;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 5,
                decoration: BoxDecoration(
                  color: AppColors.line,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Set next run',
              style: TextStyle(
                color: AppColors.text,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Choose a quick preset or adjust the time manually.',
              style: TextStyle(color: AppColors.muted, fontSize: 12),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                TimePresetChip(label: 'Morning', hour: 8, onTap: setPreset),
                TimePresetChip(label: 'Noon', hour: 12, onTap: setPreset),
                TimePresetChip(label: 'Evening', hour: 18, onTap: setPreset),
                TimePresetChip(label: '+1 hour', hour: -1, onTap: setPreset),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.line),
              ),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.text,
                  fontSize: 48,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TimeStepper(
                    label: 'Hour',
                    onMinus: () => adjustHour(-1),
                    onPlus: () => adjustHour(1),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TimeStepper(
                    label: 'Minute',
                    onMinus: () => adjustMinute(-5),
                    onPlus: () => adjustMinute(5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      Navigator.of(
                        context,
                      ).pop(TimeOfDay(hour: hour, minute: minute));
                    },
                    child: const Text('Use time'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class TimePresetChip extends StatelessWidget {
  const TimePresetChip({
    super.key,
    required this.label,
    required this.hour,
    required this.onTap,
  });

  final String label;
  final int hour;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label),
      avatar: const Icon(LucideIcons.clock, size: 16),
      backgroundColor: Colors.white,
      side: const BorderSide(color: AppColors.line),
      onPressed: () => onTap(hour),
    );
  }
}

class TimeStepper extends StatelessWidget {
  const TimeStepper({
    super.key,
    required this.label,
    required this.onMinus,
    required this.onPlus,
  });

  final String label;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Decrease $label',
            onPressed: onMinus,
            icon: const Icon(LucideIcons.minus),
          ),
          Expanded(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.text,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Increase $label',
            onPressed: onPlus,
            icon: const Icon(LucideIcons.plus),
          ),
        ],
      ),
    );
  }
}

class DemoNotice extends StatelessWidget {
  const DemoNotice({super.key});

  @override
  Widget build(BuildContext context) {
    return const SoftCard(
      child: Row(
        children: [
          Icon(LucideIcons.info, color: AppColors.tealDark),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Controls are demo-only until ESP32 command endpoints are added.',
              style: TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

/// Formats an API timestamp in the device's local timezone without adding a
/// date-formatting dependency to the mobile app.
String formatLocalTimestamp(DateTime value) {
  final local = value.toLocal();
  const months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final period = local.hour < 12 ? 'AM' : 'PM';
  return '${months[local.month - 1]} ${local.day}, ${local.year} · $hour:$minute $period';
}

String formatDurationSeconds(int seconds) {
  final minutes = seconds < 0 ? 0 : seconds ~/ 60;
  if (minutes < 60) return '$minutes min';
  final hours = minutes ~/ 60;
  final remainingMinutes = minutes % 60;
  if (hours < 24) {
    return remainingMinutes == 0
        ? '${hours}h'
        : '${hours}h ${remainingMinutes}m';
  }
  final days = hours ~/ 24;
  final remainingHours = hours % 24;
  return remainingHours == 0 ? '${days}d' : '${days}d ${remainingHours}h';
}

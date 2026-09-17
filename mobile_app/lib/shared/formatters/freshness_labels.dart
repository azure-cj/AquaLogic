/// Converts legacy/demo report prefixes into the short freshness vocabulary
/// used by current-reading surfaces.
String formatFreshnessLabel(String label) {
  var value = label.trim();
  final lowerValue = value.toLowerCase();

  if (lowerValue.startsWith('updated ')) {
    value = value.substring('updated '.length).trim();
  } else if (lowerValue.startsWith('last report ')) {
    value = value.substring('last report '.length).trim();
  }

  if (value.toLowerCase() == 'just now') return 'Just now';
  if (value.toLowerCase() == 'no recent report') return 'No recent report';
  return value;
}

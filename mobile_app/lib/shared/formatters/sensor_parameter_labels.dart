/// Consistent labels for backend sensor parameter identifiers.
String sensorParameterLabel(String parameter) =>
    switch (parameter.trim().toLowerCase()) {
      'temperature' => 'Temperature',
      'ph' => 'pH',
      'turbidity' => 'Turbidity',
      'tds' => 'TDS',
      'dissolved_oxygen' => 'Dissolved oxygen',
      'ammonia' => 'Ammonia',
      _ => _humanize(parameter),
    };

String _humanize(String value) {
  final words = value.trim().replaceAll('_', ' ').replaceAll('-', ' ');
  if (words.isEmpty) return 'Unknown parameter';
  return words[0].toUpperCase() + words.substring(1);
}

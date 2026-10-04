import 'package:aqualogic/features/alerts/data/alert_api_models.dart';
import 'package:aqualogic/features/alerts/models/alert_context.dart';
import 'package:aqualogic/features/alerts/models/alert_info.dart';

Map<String, dynamic> _map(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Expected context object.');
  }
  return value;
}

String _string(Map<String, dynamic> data, String key) {
  final value = data[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('Invalid $key.');
  }
  return value;
}

double? _number(Object? value) {
  if (value == null) return null;
  if (value is! num || !value.isFinite) {
    throw const FormatException('Invalid context number.');
  }
  return value.toDouble();
}

AlertContextReading? _reading(Object? value) {
  if (value == null) return null;
  final data = _map(value);
  if (data['reading_id'] is! int) {
    throw const FormatException('Invalid reading ID.');
  }
  final freshness = _string(data, 'reporting_freshness');
  if (!['fresh', 'stale'].contains(freshness)) {
    throw const FormatException('Invalid reporting freshness.');
  }
  return AlertContextReading(
    id: data['reading_id'] as int,
    value: _number(data['value']),
    unit: _string(data, 'unit'),
    observedAt: DateTime.parse(_string(data, 'observed_at')),
    receivedAt: DateTime.parse(_string(data, 'received_at')),
    reportingFreshness: freshness,
  );
}

AlertContextThreshold? _threshold(Object? value) {
  if (value == null) return null;
  final data = _map(value);
  if (data['enabled'] is! bool ||
      !['tank', 'global'].contains(data['source'])) {
    throw const FormatException('Invalid context threshold.');
  }
  return AlertContextThreshold(
    unit: _string(data, 'unit'),
    warningMin: _number(data['warning_min']),
    warningMax: _number(data['warning_max']),
    criticalMin: _number(data['critical_min']),
    criticalMax: _number(data['critical_max']),
    enabled: data['enabled'] as bool,
    source: _string(data, 'source'),
  );
}

class AlertContextDto {
  AlertContextDto.fromJson(Object? value) : data = _map(value);
  final Map<String, dynamic> data;
  AlertReadDto get alert => AlertReadDto.fromJson(data['alert']);
  Map<String, dynamic> get tank => _map(data['tank']);
  String get tankName => _string(tank, 'display_name');
  AlertContext toDomain(AlertInfo authoritativeAlert) {
    final lifecycle = _string(tank, 'lifecycle');
    if (!['active', 'retired'].contains(lifecycle) ||
        tank['id'] != alert.tankId) {
      throw const FormatException('Invalid context tank.');
    }
    final guidance = _map(data['guidance']);
    final direction = _string(guidance, 'direction');
    final checks = guidance['checks'];
    if (!['above', 'below', 'unavailable'].contains(direction) ||
        checks is! List ||
        checks.any((item) => item is! String)) {
      throw const FormatException('Invalid guidance.');
    }
    return AlertContext(
      alert: authoritativeAlert,
      tankLifecycle: lifecycle,
      evaluatedAt: DateTime.parse(_string(data, 'evaluated_at')),
      linkedReading: _reading(data['linked_reading']),
      latestReading: _reading(data['latest_reading']),
      linkedThreshold: _threshold(data['linked_threshold']),
      currentThreshold: _threshold(data['current_threshold']),
      code: _string(guidance, 'code'),
      direction: direction,
      explanation: _string(guidance, 'explanation'),
      checks: List<String>.unmodifiable(checks),
      advisory: _string(guidance, 'advisory'),
      speciesContext: _speciesContext(data['species_context']),
    );
  }
}

AlertSpeciesContext? _speciesContext(Object? value) {
  if (value == null) return null;
  final data = _map(value);
  final counts = _map(data['counts']);
  final species = data['species'];
  if (data['basis'] != 'current_assignments_latest_reading' ||
      !['available', 'unavailable', 'unsupported'].contains(data['status']) ||
      species is! List ||
      [
        'assigned',
        'evaluable',
        'within',
        'outside',
        'unavailable',
      ].any((key) => counts[key] is! int || (counts[key] as int) < 0)) {
    throw const FormatException('Invalid species context.');
  }
  final reading = data['reading'] == null ? null : _map(data['reading']);
  if (reading != null && reading['reading_id'] is! int) {
    throw const FormatException('Invalid species reading.');
  }
  return AlertSpeciesContext(
    parameter: _string(data, 'parameter'),
    status: _string(data, 'status'),
    reason: data['reason'] == null ? null : _string(data, 'reason'),
    unit: _string(data, 'unit'),
    readingId: reading?['reading_id'] as int?,
    observedAt: reading == null
        ? null
        : DateTime.parse(_string(reading, 'observed_at')),
    receivedAt: reading == null
        ? null
        : DateTime.parse(_string(reading, 'received_at')),
    counts: {
      for (final key in [
        'assigned',
        'evaluable',
        'within',
        'outside',
        'unavailable',
      ])
        key: counts[key] as int,
    },
    species: species
        .map((item) {
          final row = _map(item);
          if (row['species_id'] is! int ||
              !['within', 'outside', 'unavailable'].contains(row['result'])) {
            throw const FormatException('Invalid species preference.');
          }
          return AlertSpeciesPreference(
            id: row['species_id'] as int,
            name: _string(row, 'name'),
            minimum: _number(row['stored_min']),
            maximum: _number(row['stored_max']),
            result: _string(row, 'result'),
            reason: _string(row, 'reason'),
          );
        })
        .toList(growable: false),
    advisory: _string(data, 'advisory'),
  );
}

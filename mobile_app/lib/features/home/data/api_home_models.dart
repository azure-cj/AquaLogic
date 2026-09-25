export '../../tanks/data/tank_api_models.dart' show FleetTankDto;

/// Small DTOs for the Home endpoints. These intentionally parse only fields
/// used by the Home domain mapper; widgets never receive wire-format JSON.
/// FleetTankDto is shared with Tanks so both surfaces use the same status and
/// identity parsing for the backend's /fleet resource.

class HomeAlertDto {
  const HomeAlertDto({
    required this.id,
    required this.tankId,
    required this.parameter,
    required this.severity,
    required this.message,
    required this.isResolved,
    required this.createdAt,
  });

  final int id;
  final int tankId;
  final String parameter;
  final String severity;
  final String message;
  final bool isResolved;
  final DateTime createdAt;

  factory HomeAlertDto.fromJson(Object? value) {
    final json = _jsonMap(value, 'alert');
    final severity = _requiredString(json, 'severity');
    if (severity != 'warning' && severity != 'critical') {
      throw const FormatException('Unknown alert severity.');
    }
    return HomeAlertDto(
      id: _requiredInt(json, 'id'),
      tankId: _requiredInt(json, 'tank_id'),
      parameter: _requiredString(json, 'parameter'),
      severity: severity,
      message: _requiredString(json, 'message'),
      isResolved: _requiredBool(json, 'is_resolved'),
      createdAt: _requiredUtcDateTime(json, 'created_at'),
    );
  }
}

class MonitoringIncidentDto {
  const MonitoringIncidentDto({
    required this.id,
    required this.tankId,
    required this.tankName,
    required this.tankLifecycle,
    required this.state,
    required this.startedAt,
    required this.detectedAt,
    required this.lastReadingReceivedAt,
    required this.lastReportAgeSeconds,
    required this.durationSeconds,
  });

  final int id;
  final int tankId;
  final String tankName;
  final String tankLifecycle;
  final String state;
  final DateTime startedAt;
  final DateTime detectedAt;
  final DateTime? lastReadingReceivedAt;
  final int? lastReportAgeSeconds;
  final int durationSeconds;

  factory MonitoringIncidentDto.fromJson(Object? value) {
    final json = _jsonMap(value, 'monitoring incident');
    final state = _requiredString(json, 'state');
    final lifecycle = _requiredString(json, 'tank_lifecycle');
    if (state != 'active' && state != 'resolved') {
      throw const FormatException('Unknown monitoring incident state.');
    }
    if (lifecycle != 'active' && lifecycle != 'retired') {
      throw const FormatException('Unknown tank lifecycle.');
    }
    return MonitoringIncidentDto(
      id: _requiredInt(json, 'id'),
      tankId: _requiredInt(json, 'tank_id'),
      tankName: _requiredString(json, 'tank_name'),
      tankLifecycle: lifecycle,
      state: state,
      startedAt: _requiredUtcDateTime(json, 'started_at'),
      detectedAt: _requiredUtcDateTime(json, 'detected_at'),
      lastReadingReceivedAt: _optionalUtcDateTime(
        json,
        'last_reading_received_at',
      ),
      lastReportAgeSeconds: _optionalInt(json, 'last_report_age_seconds'),
      durationSeconds: _requiredInt(json, 'duration_seconds'),
    );
  }
}

class MonitoringIncidentPageDto {
  const MonitoringIncidentPageDto({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.total,
    required this.totalPages,
    required this.hasNext,
  });

  final List<MonitoringIncidentDto> items;
  final int page;
  final int pageSize;
  final int total;
  final int totalPages;
  final bool hasNext;

  factory MonitoringIncidentPageDto.fromJson(Object? value) {
    final json = _jsonMap(value, 'monitoring incident page');
    final rawItems = json['items'];
    if (rawItems is! List) {
      throw const FormatException('Expected monitoring incident items.');
    }
    return MonitoringIncidentPageDto(
      items: rawItems.map(MonitoringIncidentDto.fromJson).toList(),
      page: _requiredInt(json, 'page'),
      pageSize: _requiredInt(json, 'page_size'),
      total: _requiredInt(json, 'total'),
      totalPages: _requiredInt(json, 'total_pages'),
      hasNext: _requiredBool(json, 'has_next'),
    );
  }
}

Map<String, Object?> _jsonMap(Object? value, String label) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw FormatException('Expected a JSON object for $label.');
      }
      result[entry.key as String] = entry.value;
    }
    return result;
  }
  throw FormatException('Expected a JSON object for $label.');
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String) return value;
  throw FormatException('Expected string field $key.');
}

int _requiredInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is int) return value;
  throw FormatException('Expected integer field $key.');
}

int? _optionalInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is int) return value;
  throw FormatException('Expected nullable integer field $key.');
}

bool _requiredBool(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is bool) return value;
  throw FormatException('Expected boolean field $key.');
}

DateTime _requiredUtcDateTime(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String) {
    final date = DateTime.tryParse(value);
    if (date != null) return date.toUtc();
  }
  throw FormatException('Expected ISO timestamp field $key.');
}

DateTime? _optionalUtcDateTime(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is String) {
    final date = DateTime.tryParse(value);
    if (date != null) return date.toUtc();
  }
  throw FormatException('Expected nullable ISO timestamp field $key.');
}

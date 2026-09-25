/// Wire-format DTOs for FastAPI alert and monitoring-incident responses.
/// Widgets and domain models do not depend on snake_case API field names.
class AlertReadDto {
  const AlertReadDto({
    required this.id,
    required this.tankId,
    required this.parameter,
    required this.severity,
    required this.message,
    required this.isResolved,
    required this.createdAt,
    this.readingId,
    this.resolvedAt,
    this.resolvedByUserId,
    this.resolutionSource,
  });

  final int id;
  final int tankId;
  final int? readingId;
  final String parameter;
  final String severity;
  final String message;
  final bool isResolved;
  final DateTime createdAt;
  final DateTime? resolvedAt;
  final int? resolvedByUserId;
  final String? resolutionSource;

  factory AlertReadDto.fromJson(Object? value) {
    final json = _jsonMap(value, 'alert');
    return AlertReadDto(
      id: _requiredInt(json, 'id'),
      tankId: _requiredInt(json, 'tank_id'),
      readingId: _optionalInt(json, 'reading_id'),
      parameter: _requiredString(json, 'parameter'),
      severity: _requiredString(json, 'severity'),
      message: _requiredString(json, 'message'),
      isResolved: _requiredBool(json, 'is_resolved'),
      createdAt: _requiredDateTime(json, 'created_at'),
      resolvedAt: _optionalDateTime(json, 'resolved_at'),
      resolvedByUserId: _optionalInt(json, 'resolved_by_user_id'),
      resolutionSource: _optionalString(json, 'resolution_source'),
    );
  }
}

class MonitoringIncidentReadDto {
  const MonitoringIncidentReadDto({
    required this.id,
    required this.tankId,
    required this.tankName,
    required this.tankLifecycle,
    required this.state,
    required this.startedAt,
    required this.detectedAt,
    required this.lastReportAgeSeconds,
    required this.durationSeconds,
    this.lastReadingReceivedAt,
    this.resolvedAt,
    this.resolutionReason,
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
  final DateTime? resolvedAt;
  final String? resolutionReason;
  final int durationSeconds;

  factory MonitoringIncidentReadDto.fromJson(Object? value) {
    final json = _jsonMap(value, 'monitoring incident');
    return MonitoringIncidentReadDto(
      id: _requiredInt(json, 'id'),
      tankId: _requiredInt(json, 'tank_id'),
      tankName: _requiredString(json, 'tank_name'),
      tankLifecycle: _requiredString(json, 'tank_lifecycle'),
      state: _requiredString(json, 'state'),
      startedAt: _requiredDateTime(json, 'started_at'),
      detectedAt: _requiredDateTime(json, 'detected_at'),
      lastReadingReceivedAt: _optionalDateTime(
        json,
        'last_reading_received_at',
      ),
      lastReportAgeSeconds: _optionalInt(json, 'last_report_age_seconds'),
      resolvedAt: _optionalDateTime(json, 'resolved_at'),
      resolutionReason: _optionalString(json, 'resolution_reason'),
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
    required this.hasPrevious,
    required this.hasNext,
  });

  final List<MonitoringIncidentReadDto> items;
  final int page;
  final int pageSize;
  final int total;
  final int totalPages;
  final bool hasPrevious;
  final bool hasNext;

  factory MonitoringIncidentPageDto.fromJson(Object? value) {
    final json = _jsonMap(value, 'monitoring incident page');
    final rawItems = json['items'];
    if (rawItems is! List) {
      throw const FormatException('Expected monitoring incident items.');
    }
    return MonitoringIncidentPageDto(
      items: rawItems.map(MonitoringIncidentReadDto.fromJson).toList(),
      page: _requiredInt(json, 'page'),
      pageSize: _requiredInt(json, 'page_size'),
      total: _requiredInt(json, 'total'),
      totalPages: _requiredInt(json, 'total_pages'),
      hasPrevious: _requiredBool(json, 'has_previous'),
      hasNext: _requiredBool(json, 'has_next'),
    );
  }
}

class TankAlertNameDto {
  const TankAlertNameDto({required this.id, required this.name});

  final int id;
  final String name;

  factory TankAlertNameDto.fromJson(Object? value) {
    final json = _jsonMap(value, 'tank name');
    return TankAlertNameDto(
      id: _requiredInt(json, 'id'),
      name: _requiredString(json, 'name'),
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

String? _optionalString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is String) return value;
  throw FormatException('Expected nullable string field $key.');
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

DateTime _requiredDateTime(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String) {
    final date = DateTime.tryParse(value);
    if (date != null) return date.toUtc();
  }
  throw FormatException('Expected ISO timestamp field $key.');
}

DateTime? _optionalDateTime(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is String) {
    final date = DateTime.tryParse(value);
    if (date != null) return date.toUtc();
  }
  throw FormatException('Expected nullable ISO timestamp field $key.');
}

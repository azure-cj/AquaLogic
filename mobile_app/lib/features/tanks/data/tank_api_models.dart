/// Tank-related API DTOs. These parse FastAPI's snake_case wire contract and
/// keep it separate from the presentation models used by the widgets.
class FleetTankDto {
  const FleetTankDto({
    required this.id,
    required this.name,
    required this.location,
    required this.status,
    required this.reportingAgeSeconds,
    required this.lastReadingAt,
    required this.activeWarningCount,
    required this.activeCriticalCount,
    required this.activeMonitoringIncidentCount,
    required this.speciesCareStatus,
    required this.assignedSpeciesCount,
    this.latestReading,
  });

  final int id;
  final String name;
  final String location;
  final String status;
  final int? reportingAgeSeconds;
  final DateTime? lastReadingAt;
  final int activeWarningCount;
  final int activeCriticalCount;
  final int activeMonitoringIncidentCount;
  final String speciesCareStatus;
  final int assignedSpeciesCount;
  final SensorReadingDto? latestReading;

  factory FleetTankDto.fromJson(Object? value) {
    final json = _jsonMap(value, 'fleet tank');
    return FleetTankDto(
      id: _requiredInt(json, 'id'),
      name: _requiredString(json, 'name'),
      location: _requiredString(json, 'location'),
      status: _requiredString(json, 'status'),
      reportingAgeSeconds: _optionalInt(json, 'reporting_age_seconds'),
      lastReadingAt: _optionalDateTime(json, 'last_reading_at'),
      activeWarningCount: _requiredInt(json, 'active_warning_count'),
      activeCriticalCount: _requiredInt(json, 'active_critical_count'),
      activeMonitoringIncidentCount: _requiredInt(
        json,
        'active_monitoring_incident_count',
      ),
      speciesCareStatus: _requiredString(json, 'species_care_status'),
      assignedSpeciesCount: _requiredInt(json, 'assigned_species_count'),
      latestReading: json['latest_reading'] == null
          ? null
          : SensorReadingDto.fromJson(json['latest_reading']),
    );
  }
}

class TankRecordDto {
  const TankRecordDto({
    required this.id,
    required this.name,
    required this.location,
    required this.lifecycle,
    required this.createdAt,
    required this.fishSpecies,
    this.description,
    this.habitatLabel,
    this.waterType,
    this.volumeLiters,
  });

  final int id;
  final String name;
  final String location;
  final String lifecycle;
  final DateTime createdAt;
  final String? description;
  final String? habitatLabel;
  final String? waterType;
  final int? volumeLiters;
  final List<AssignedSpeciesDto> fishSpecies;

  factory TankRecordDto.fromJson(Object? value) {
    final json = _jsonMap(value, 'tank');
    final rawSpecies = json['fish_species'];
    if (rawSpecies is! List) {
      throw const FormatException('Expected tank species list.');
    }
    final lifecycle = _requiredString(json, 'lifecycle');
    if (lifecycle != 'active' && lifecycle != 'retired') {
      throw const FormatException('Unknown tank lifecycle.');
    }
    return TankRecordDto(
      id: _requiredInt(json, 'id'),
      name: _requiredString(json, 'name'),
      location: _requiredString(json, 'location'),
      lifecycle: lifecycle,
      createdAt: _requiredDateTime(json, 'created_at'),
      description: _optionalString(json, 'description'),
      habitatLabel: _optionalString(json, 'habitat_label'),
      waterType: _optionalString(json, 'water_type'),
      volumeLiters: _optionalInt(json, 'volume_liters'),
      fishSpecies: rawSpecies.map(AssignedSpeciesDto.fromJson).toList(),
    );
  }
}

class AssignedSpeciesDto {
  const AssignedSpeciesDto({
    required this.id,
    required this.commonName,
    required this.scientificName,
  });

  final int id;
  final String commonName;
  final String scientificName;

  factory AssignedSpeciesDto.fromJson(Object? value) {
    final json = _jsonMap(value, 'assigned species');
    return AssignedSpeciesDto(
      id: _requiredInt(json, 'id'),
      commonName: _requiredString(json, 'common_name'),
      scientificName: _requiredString(json, 'scientific_name'),
    );
  }
}

class SensorReadingDto {
  const SensorReadingDto({
    required this.id,
    required this.tankId,
    required this.timestamp,
    required this.receivedAt,
    required this.isMock,
    required this.temperature,
    required this.ph,
    required this.turbidity,
    required this.tds,
  });

  final int id;
  final int tankId;
  final DateTime timestamp;
  final DateTime receivedAt;
  final bool isMock;
  final double? temperature;
  final double? ph;
  final double? turbidity;
  final double? tds;

  double? valueFor(String parameter) => switch (parameter) {
    'temperature' => temperature,
    'ph' => ph,
    'turbidity' => turbidity,
    'tds' => tds,
    _ => null,
  };

  factory SensorReadingDto.fromJson(Object? value) {
    final json = _jsonMap(value, 'sensor reading');
    return SensorReadingDto(
      id: _requiredInt(json, 'id'),
      tankId: _requiredInt(json, 'tank_id'),
      timestamp: _requiredDateTime(json, 'timestamp'),
      receivedAt: _requiredDateTime(json, 'received_at'),
      isMock: _requiredBool(json, 'is_mock'),
      temperature: _optionalDouble(json, 'temperature'),
      ph: _optionalDouble(json, 'ph'),
      turbidity: _optionalDouble(json, 'turbidity'),
      tds: _optionalDouble(json, 'tds'),
    );
  }
}

class TankOperationsDto {
  const TankOperationsDto({
    required this.tankId,
    required this.evaluatedAt,
    required this.status,
    required this.latestReading,
    required this.parameterStatuses,
    required this.activeAlerts,
  });

  final int tankId;
  final DateTime evaluatedAt;
  final String status;
  final SensorReadingDto? latestReading;
  final Map<String, String> parameterStatuses;
  final List<TankAlertDto> activeAlerts;

  factory TankOperationsDto.fromJson(Object? value) {
    final json = _jsonMap(value, 'tank operations');
    final rawStatuses = json['parameter_statuses'];
    if (rawStatuses is! Map) {
      throw const FormatException('Expected parameter status map.');
    }
    final statuses = <String, String>{};
    for (final entry in rawStatuses.entries) {
      if (entry.key is! String || entry.value is! String) {
        throw const FormatException('Invalid parameter status entry.');
      }
      statuses[entry.key as String] = entry.value as String;
    }
    final rawAlerts = json['active_alerts'];
    if (rawAlerts is! List) {
      throw const FormatException('Expected active alert list.');
    }
    return TankOperationsDto(
      tankId: _requiredInt(json, 'tank_id'),
      evaluatedAt: _requiredDateTime(json, 'evaluated_at'),
      status: _requiredString(json, 'status'),
      latestReading: json['latest_reading'] == null
          ? null
          : SensorReadingDto.fromJson(json['latest_reading']),
      parameterStatuses: Map.unmodifiable(statuses),
      activeAlerts: rawAlerts.map(TankAlertDto.fromJson).toList(),
    );
  }
}

class TankAlertDto {
  const TankAlertDto({
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

  factory TankAlertDto.fromJson(Object? value) {
    final json = _jsonMap(value, 'tank alert');
    return TankAlertDto(
      id: _requiredInt(json, 'id'),
      tankId: _requiredInt(json, 'tank_id'),
      parameter: _requiredString(json, 'parameter'),
      severity: _requiredString(json, 'severity'),
      message: _requiredString(json, 'message'),
      isResolved: _requiredBool(json, 'is_resolved'),
      createdAt: _requiredDateTime(json, 'created_at'),
    );
  }
}

class TankMonitoringPageDto {
  const TankMonitoringPageDto({required this.items});

  final List<TankMonitoringIncidentDto> items;

  factory TankMonitoringPageDto.fromJson(Object? value) {
    final json = _jsonMap(value, 'monitoring incidents page');
    final rawItems = json['items'];
    if (rawItems is! List) {
      throw const FormatException('Expected monitoring incident items.');
    }
    return TankMonitoringPageDto(
      items: rawItems.map(TankMonitoringIncidentDto.fromJson).toList(),
    );
  }
}

class TankMonitoringIncidentDto {
  const TankMonitoringIncidentDto({
    required this.id,
    required this.tankId,
    required this.tankLifecycle,
    required this.state,
    required this.startedAt,
    required this.detectedAt,
    required this.lastReportAgeSeconds,
    required this.durationSeconds,
  });

  final int id;
  final int tankId;
  final String tankLifecycle;
  final String state;
  final DateTime startedAt;
  final DateTime detectedAt;
  final int? lastReportAgeSeconds;
  final int durationSeconds;

  factory TankMonitoringIncidentDto.fromJson(Object? value) {
    final json = _jsonMap(value, 'monitoring incident');
    final lifecycle = _requiredString(json, 'tank_lifecycle');
    final state = _requiredString(json, 'state');
    if ((lifecycle != 'active' && lifecycle != 'retired') ||
        (state != 'active' && state != 'resolved')) {
      throw const FormatException('Unknown monitoring incident state.');
    }
    return TankMonitoringIncidentDto(
      id: _requiredInt(json, 'id'),
      tankId: _requiredInt(json, 'tank_id'),
      tankLifecycle: lifecycle,
      state: state,
      startedAt: _requiredDateTime(json, 'started_at'),
      detectedAt: _requiredDateTime(json, 'detected_at'),
      lastReportAgeSeconds: _optionalInt(json, 'last_report_age_seconds'),
      durationSeconds: _requiredInt(json, 'duration_seconds'),
    );
  }
}

class TankSuitabilityDto {
  const TankSuitabilityDto({required this.tankId, required this.species});

  final int tankId;
  final List<TankSuitableSpeciesDto> species;

  factory TankSuitabilityDto.fromJson(Object? value) {
    final json = _jsonMap(value, 'tank species suitability');
    final rawSpecies = json['species'];
    if (rawSpecies is! List) {
      throw const FormatException('Expected suitability species list.');
    }
    return TankSuitabilityDto(
      tankId: _requiredInt(json, 'tank_id'),
      species: rawSpecies.map(TankSuitableSpeciesDto.fromJson).toList(),
    );
  }
}

class TankSuitableSpeciesDto {
  const TankSuitableSpeciesDto({required this.speciesId, required this.status});

  final int speciesId;
  final String status;

  factory TankSuitableSpeciesDto.fromJson(Object? value) {
    final json = _jsonMap(value, 'species suitability');
    final status = _requiredString(json, 'status');
    if (status != 'suitable' &&
        status != 'attention' &&
        status != 'unavailable') {
      throw const FormatException('Unknown species suitability state.');
    }
    return TankSuitableSpeciesDto(
      speciesId: _requiredInt(json, 'fish_species_id'),
      status: status,
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

double? _optionalDouble(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is num && value.isFinite) return value.toDouble();
  throw FormatException('Expected nullable numeric field $key.');
}

bool _requiredBool(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is bool) return value;
  throw FormatException('Expected boolean field $key.');
}

DateTime _requiredDateTime(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) return parsed.toUtc();
  }
  throw FormatException('Expected ISO timestamp field $key.');
}

DateTime? _optionalDateTime(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) return parsed.toUtc();
  }
  throw FormatException('Expected nullable ISO timestamp field $key.');
}

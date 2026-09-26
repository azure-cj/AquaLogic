import 'package:aqualogic/features/fish/models/fish_species.dart';

class FishSpeciesDto {
  const FishSpeciesDto({
    required this.id,
    required this.commonName,
    required this.scientificName,
    required this.category,
    required this.description,
    required this.idealTempMin,
    required this.idealTempMax,
    required this.idealPhMin,
    required this.idealPhMax,
    required this.idealTdsMin,
    required this.idealTdsMax,
    required this.diet,
    required this.dietType,
    required this.compatibilityNotes,
    required this.careTips,
  });

  final int id;
  final String commonName;
  final String scientificName;
  final String category;
  final String? description;
  final double? idealTempMin;
  final double? idealTempMax;
  final double? idealPhMin;
  final double? idealPhMax;
  final double? idealTdsMin;
  final double? idealTdsMax;
  final String? diet;
  final String? dietType;
  final String? compatibilityNotes;
  final String? careTips;

  factory FishSpeciesDto.fromJson(Object? value) {
    final json = _jsonMap(value);
    return FishSpeciesDto(
      id: _requiredInt(json, 'id'),
      commonName: _requiredString(json, 'common_name'),
      scientificName: _requiredString(json, 'scientific_name'),
      category: _requiredString(json, 'category'),
      description: _optionalString(json, 'description'),
      idealTempMin: _optionalDouble(json, 'ideal_temp_min'),
      idealTempMax: _optionalDouble(json, 'ideal_temp_max'),
      idealPhMin: _optionalDouble(json, 'ideal_ph_min'),
      idealPhMax: _optionalDouble(json, 'ideal_ph_max'),
      idealTdsMin: _optionalDouble(json, 'ideal_tds_min'),
      idealTdsMax: _optionalDouble(json, 'ideal_tds_max'),
      diet: _optionalString(json, 'diet'),
      dietType: _optionalString(json, 'diet_type'),
      compatibilityNotes: _optionalString(json, 'compatibility_notes'),
      careTips: _optionalString(json, 'care_tips'),
    );
  }

  FishSpecies toDomain() => FishSpecies(
    id: id.toString(),
    name: commonName,
    scientificName: scientificName,
    // The backend has no freshwater/saltwater field. An empty value suppresses
    // the demo-only water-type treatment instead of guessing from category.
    type: '',
    category: category,
    careGroup: category,
    temperatureRange: _range(idealTempMin, idealTempMax, '°C'),
    phRange: _range(idealPhMin, idealPhMax, ''),
    tdsRange: _range(idealTdsMin, idealTdsMax, 'ppm'),
    diet: _firstText(diet, dietType) ?? 'Not specified by AquaLogic.',
    description: _clean(description) ?? '',
    careNote: _clean(careTips) ?? '',
    compatibilityNote: _clean(compatibilityNotes) ?? '',
  );
}

String _range(double? minimum, double? maximum, String unit) {
  final suffix = unit.isEmpty ? '' : ' $unit';
  if (minimum == null && maximum == null) return 'Not specified';
  if (minimum != null && maximum != null) {
    return '${_number(minimum)}–${_number(maximum)}$suffix';
  }
  if (minimum != null) return '≥ ${_number(minimum)}$suffix';
  return '≤ ${_number(maximum!)}$suffix';
}

String _number(double value) =>
    value == value.truncateToDouble() ? value.toInt().toString() : '$value';

String? _firstText(String? first, String? second) =>
    _clean(first) ?? _clean(second);

String? _clean(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

Map<String, Object?> _jsonMap(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw const FormatException('Expected a species object.');
      }
      result[entry.key as String] = entry.value;
    }
    return result;
  }
  throw const FormatException('Expected a species object.');
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String && value.trim().isNotEmpty) return value;
  throw FormatException('Expected species field $key.');
}

String? _optionalString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is String) return value;
  throw FormatException('Expected nullable species field $key.');
}

int _requiredInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is int && value > 0) return value;
  throw FormatException('Expected positive integer species field $key.');
}

double? _optionalDouble(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is num && value.isFinite) return value.toDouble();
  throw FormatException('Expected nullable numeric species field $key.');
}

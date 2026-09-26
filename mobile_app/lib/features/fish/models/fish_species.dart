import 'package:aqualogic/shared/models/aqualogic_status.dart';

class FishSpecies {
  const FishSpecies({
    required this.name,
    required this.scientificName,
    required this.type,
    required this.temperatureRange,
    required this.phRange,
    required this.careNote,
    this.id,
    this.category = '',
    this.tdsRange = 'Not specified',
    this.diet = 'Not specified',
    this.description = '',
    this.careGroup = 'General care',
    this.compatibilityNote = 'Review tank mates and available space.',
  });

  final String? id;
  final String name;
  final String scientificName;

  /// Present only for local demo fixtures. The backend has no water-type field.
  final String type;

  /// Backend directory category; it must not be interpreted as water type.
  final String category;
  final String temperatureRange;
  final String phRange;
  final String tdsRange;
  final String diet;
  final String description;
  final String careNote;
  final String careGroup;
  final String compatibilityNote;

  String get speciesId => id ?? _slugify(name);
}

class AssignedFishSpecies {
  const AssignedFishSpecies({
    required this.species,
    required this.suitability,
    this.count,
    this.explanation,
  });

  final FishSpecies species;
  final SpeciesSuitability suitability;
  final int? count;
  final String? explanation;
}

String _slugify(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
}

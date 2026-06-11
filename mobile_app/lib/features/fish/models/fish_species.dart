class FishSpecies {
  const FishSpecies({
    required this.name,
    required this.scientificName,
    required this.type,
    required this.temperatureRange,
    required this.phRange,
    required this.careNote,
  });

  final String name;
  final String scientificName;
  final String type;
  final String temperatureRange;
  final String phRange;
  final String careNote;
}

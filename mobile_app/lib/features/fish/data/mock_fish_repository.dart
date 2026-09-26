import 'package:aqualogic/features/demo/demo_data.dart';
import 'package:aqualogic/features/fish/models/fish_species.dart';

abstract class FishRepository {
  bool get isLiveData;

  bool get supportsWaterTypeFilter;

  Future<List<FishSpecies>> list();

  Future<FishSpecies?> findById(String speciesId);
}

/// Local species directory and tank assignments. It models the future fish
/// and species-suitability routes without coupling widgets to DemoData.
class MockFishRepository implements FishRepository {
  const MockFishRepository();

  @override
  bool get isLiveData => false;

  @override
  bool get supportsWaterTypeFilter => true;

  @override
  Future<List<FishSpecies>> list() async => DemoData.fishLibrary;

  @override
  Future<FishSpecies?> findById(String speciesId) async {
    for (final species in DemoData.fishLibrary) {
      if (species.speciesId == speciesId) return species;
    }
    return null;
  }
}

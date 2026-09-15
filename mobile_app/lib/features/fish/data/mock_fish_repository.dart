import 'package:aqualogic/features/demo/demo_data.dart';
import 'package:aqualogic/features/fish/models/fish_species.dart';
import 'package:aqualogic/features/sensors/models/sensor_snapshot.dart';
import 'package:aqualogic/features/tanks/models/tank_info.dart';
import 'package:aqualogic/shared/models/aqualogic_status.dart';

abstract class FishRepository {
  List<FishSpecies> list();

  FishSpecies? findById(String speciesId);

  List<AssignedFishSpecies> assignedToTank(
    String tankId, {
    required SensorSnapshot snapshot,
  });
}

/// Local species directory and tank assignments. It models the future fish
/// and species-suitability routes without coupling widgets to DemoData.
class MockFishRepository implements FishRepository {
  const MockFishRepository();

  @override
  List<FishSpecies> list() => DemoData.fishLibrary;

  @override
  FishSpecies? findById(String speciesId) {
    for (final species in list()) {
      if (species.speciesId == speciesId) return species;
    }
    return null;
  }

  @override
  List<AssignedFishSpecies> assignedToTank(
    String tankId, {
    required SensorSnapshot snapshot,
  }) {
    TankInfo? tank;
    for (final item in DemoData.tanks) {
      if (item.tankId == tankId) {
        tank = item;
        break;
      }
    }
    if (tank == null) return const [];
    return [
      for (final assigned in tank.species)
        if (findById(assigned.speciesId) case final species?)
          AssignedFishSpecies(
            species: species,
            suitability: !snapshot.isOnline
                ? SpeciesSuitability.unavailable
                : assigned.suitability,
          ),
    ];
  }
}

import 'package:aqualogic/features/fish/models/fish_species.dart';
import 'package:aqualogic/features/tanks/models/tank_info.dart';

class DemoData {
  static const tanks = [
    TankInfo(
      initial: 'D',
      name: 'Display Reef A',
      subtitle: 'Mixed reef - 320L',
      status: 'NORMAL',
      health: 94,
      typeLabel: 'Mixed reef',
      volumeLabel: '320L',
      lastFedLabel: '2h ago',
      description: 'Primary display tank with mixed coral and reef fish.',
      isSelected: true,
    ),
    TankInfo(
      initial: 'Q',
      name: 'Quarantine B',
      subtitle: 'Clownfish - 80L',
      status: 'WARNING',
      health: 81,
      typeLabel: 'Quarantine',
      volumeLabel: '80L',
      lastFedLabel: '4h ago',
      description: 'Observation tank for new or recovering livestock.',
    ),
    TankInfo(
      initial: 'F',
      name: 'Freshwater C',
      subtitle: 'Discus - 240L',
      status: 'CRITICAL',
      health: 62,
      typeLabel: 'Freshwater',
      volumeLabel: '240L',
      lastFedLabel: '1h ago',
      description: 'Warm freshwater tank tuned for discus stability.',
    ),
    TankInfo(
      initial: 'N',
      name: 'Nursery D',
      subtitle: 'Guppy fry - 60L',
      status: 'NORMAL',
      health: 88,
      typeLabel: 'Nursery',
      volumeLabel: '60L',
      lastFedLabel: '30m ago',
      description: 'Small nursery tank for fry and gentle flow.',
    ),
  ];

  static const fishLibrary = [
    FishSpecies(
      name: 'Discus',
      scientificName: 'Symphysodon aequifasciatus',
      type: 'FRESHWATER',
      temperatureRange: '28-31 °C',
      phRange: '6.0-7.0',
      careNote: 'Warm, soft, stable water; sensitive to sudden changes.',
    ),
    FishSpecies(
      name: 'Guppy',
      scientificName: 'Poecilia reticulata',
      type: 'FRESHWATER',
      temperatureRange: '22-28 °C',
      phRange: '6.8-7.8',
      careNote: 'Hardy community fish; avoid overcrowding and poor filtration.',
    ),
    FishSpecies(
      name: 'Neon Tetra',
      scientificName: 'Paracheirodon innesi',
      type: 'FRESHWATER',
      temperatureRange: '20-26 °C',
      phRange: '6.0-7.0',
      careNote: 'Best kept in groups with gentle flow and dimmer lighting.',
    ),
    FishSpecies(
      name: 'Ocellaris Clownfish',
      scientificName: 'Amphiprion ocellaris',
      type: 'SALTWATER',
      temperatureRange: '24-27 °C',
      phRange: '8.1-8.4',
      careNote: 'Stable salinity and clean marine water are more important.',
    ),
    FishSpecies(
      name: 'Yellow Tang',
      scientificName: 'Zebrasoma flavescens',
      type: 'SALTWATER',
      temperatureRange: '24-27 °C',
      phRange: '8.1-8.4',
      careNote: 'Needs strong filtration, swimming space, and algae grazing.',
    ),
    FishSpecies(
      name: 'Betta',
      scientificName: 'Betta splendens',
      type: 'FRESHWATER',
      temperatureRange: '24-30 °C',
      phRange: '6.5-7.5',
      careNote: 'Prefers warm, calm water and low-stress tank mates.',
    ),
  ];
}

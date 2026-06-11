import 'package:aqualogic/app/theme/app_colors.dart';
import 'package:aqualogic/features/demo/demo_data.dart';
import 'package:aqualogic/features/fish/models/fish_species.dart';
import 'package:aqualogic/shared/widgets/app_page.dart';
import 'package:aqualogic/shared/widgets/header_panel.dart';
import 'package:aqualogic/shared/widgets/soft_card.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class FishLibraryScreen extends StatefulWidget {
  const FishLibraryScreen({super.key});

  @override
  State<FishLibraryScreen> createState() => _FishLibraryScreenState();
}

class _FishLibraryScreenState extends State<FishLibraryScreen> {
  var query = '';

  List<FishSpecies> get filteredFish {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return DemoData.fishLibrary;
    return DemoData.fishLibrary.where((fish) {
      return fish.name.toLowerCase().contains(normalized) ||
          fish.scientificName.toLowerCase().contains(normalized) ||
          fish.type.toLowerCase().contains(normalized);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final fish = filteredFish;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        top: false,
        child: AppPage(
          header: HeaderPanel(
            compact: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconButton.filledTonal(
                  tooltip: 'Back',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(LucideIcons.arrowLeft),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Fish library',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const Text(
                  'Care references',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
                const SizedBox(height: 14),
                TextField(
                  onChanged: (value) => setState(() => query = value),
                  decoration: InputDecoration(
                    hintText: 'Search species...',
                    prefixIcon: const Icon(LucideIcons.search),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
          children: [
            if (fish.isEmpty)
              const SoftCard(
                child: Text(
                  'No fish matched your search.',
                  style: TextStyle(color: AppColors.muted),
                ),
              )
            else
              ...fish.map((species) => FishSpeciesCard(species: species)),
          ],
        ),
      ),
    );
  }
}

class FishSpeciesCard extends StatelessWidget {
  const FishSpeciesCard({super.key, required this.species});

  final FishSpecies species;

  @override
  Widget build(BuildContext context) {
    final isFreshwater = species.type == 'FRESHWATER';
    return SoftCard(
      padding: EdgeInsets.zero,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 78,
            height: 142,
            decoration: BoxDecoration(
              color: AppColors.teal.withValues(alpha: 0.72),
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(17),
              ),
            ),
            child: const Center(
              child: Icon(
                LucideIcons.fish,
                color: AppColors.tealDark,
                size: 34,
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              species.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.text,
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                              ),
                            ),
                            Text(
                              species.scientificName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.muted,
                                fontStyle: FontStyle.italic,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: isFreshwater
                              ? AppColors.mint
                              : AppColors.line.withValues(alpha: 0.68),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          species.type,
                          style: const TextStyle(
                            color: AppColors.text,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  FishMetric(label: 'Temp', value: species.temperatureRange),
                  FishMetric(label: 'pH', value: species.phRange),
                  const SizedBox(height: 8),
                  Text(
                    species.careNote,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class FishMetric extends StatelessWidget {
  const FishMetric({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          SizedBox(
            width: 42,
            child: Text(
              '$label:',
              style: const TextStyle(color: AppColors.muted, fontSize: 11),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.text,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

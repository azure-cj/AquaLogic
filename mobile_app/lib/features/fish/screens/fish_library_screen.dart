import 'package:aqualogic/app/theme/app_colors.dart';
import 'package:aqualogic/features/fish/data/mock_fish_repository.dart';
import 'package:aqualogic/features/fish/models/fish_species.dart';
import 'package:aqualogic/shared/models/aqualogic_status.dart';
import 'package:aqualogic/shared/widgets/app_page.dart';
import 'package:aqualogic/shared/widgets/header_panel.dart';
import 'package:aqualogic/shared/widgets/semantic_status_widgets.dart';
import 'package:aqualogic/shared/widgets/soft_card.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

enum FishFilter { all, freshwater, saltwater }

class FishLibraryScreen extends StatefulWidget {
  const FishLibraryScreen({
    super.key,
    this.repository,
    this.initialSpeciesId,
    this.assignedTankName,
  });

  final FishRepository? repository;
  final String? initialSpeciesId;
  final String? assignedTankName;

  @override
  State<FishLibraryScreen> createState() => _FishLibraryScreenState();
}

class _FishLibraryScreenState extends State<FishLibraryScreen> {
  late final FishRepository _repository =
      widget.repository ?? const MockFishRepository();
  var _query = '';
  var _filter = FishFilter.all;

  @override
  Widget build(BuildContext context) {
    final species = _filteredSpecies();
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
                  'Fish species',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                const Text(
                  'Practical care references for your tanks',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 14),
                TextField(
                  onChanged: (value) => setState(() => _query = value),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search species...',
                    prefixIcon: const Icon(LucideIcons.search),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(vertical: 11),
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
            if (widget.assignedTankName != null)
              _AssignedContext(tankName: widget.assignedTankName!),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Species directory',
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Text(
                  '${species.length} species',
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            _FishFilters(
              selected: _filter,
              onSelected: (filter) => setState(() => _filter = filter),
            ),
            if (species.isEmpty)
              const EmptyState(
                title: 'No species match your search',
                message: 'Try a common name, scientific name, or category.',
                icon: LucideIcons.searchX,
              )
            else
              ...species.map(
                (item) => FishSpeciesCard(
                  species: item,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => SpeciesDetailScreen(
                        speciesId: item.speciesId,
                        repository: _repository,
                        assignedTankName: widget.assignedTankName,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<FishSpecies> _filteredSpecies() {
    final normalized = _query.trim().toLowerCase();
    return _repository
        .list()
        .where((species) {
          final matchesQuery =
              normalized.isEmpty ||
              species.name.toLowerCase().contains(normalized) ||
              species.scientificName.toLowerCase().contains(normalized) ||
              species.type.toLowerCase().contains(normalized) ||
              species.careGroup.toLowerCase().contains(normalized);
          final matchesFilter = switch (_filter) {
            FishFilter.all => true,
            FishFilter.freshwater => species.type.toUpperCase() == 'FRESHWATER',
            FishFilter.saltwater => species.type.toUpperCase() == 'SALTWATER',
          };
          return matchesQuery && matchesFilter;
        })
        .toList(growable: false);
  }
}

class FishSpeciesCard extends StatelessWidget {
  const FishSpeciesCard({super.key, required this.species, this.onTap});

  final FishSpecies species;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isFreshwater = species.type.toUpperCase() == 'FRESHWATER';
    final content = Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 23,
            backgroundColor: isFreshwater
                ? AppColors.mint
                : AppColors.teal.withValues(alpha: 0.2),
            child: const Icon(
              LucideIcons.fish,
              color: AppColors.tealDark,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        species.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _TypeLabel(type: species.type),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  species.scientificName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  species.careNote,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 11,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    const Icon(
                      LucideIcons.thermometer,
                      color: AppColors.tealDark,
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        species.temperatureRange,
                        style: const TextStyle(
                          color: AppColors.text,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (onTap != null)
                      const Icon(
                        LucideIcons.chevronRight,
                        color: AppColors.muted,
                        size: 18,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return SoftCard(child: content);
    return Semantics(
      button: true,
      label: 'Open ${species.name} species details',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.line),
            ),
            child: content,
          ),
        ),
      ),
    );
  }
}

class SpeciesDetailScreen extends StatelessWidget {
  const SpeciesDetailScreen({
    super.key,
    required this.speciesId,
    this.repository,
    this.assignedTankName,
    this.suitability,
  });

  final String speciesId;
  final FishRepository? repository;
  final String? assignedTankName;
  final SpeciesSuitability? suitability;

  @override
  Widget build(BuildContext context) {
    final fishRepository = repository ?? const MockFishRepository();
    final species = fishRepository.findById(speciesId);
    if (species == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: const Text('Species detail')),
        body: const Padding(
          padding: EdgeInsets.all(16),
          child: EmptyState(
            title: 'Species unavailable',
            message: 'This local species record is not available.',
            icon: LucideIcons.circleHelp,
          ),
        ),
      );
    }

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
                  'Species detail',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  species.name,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          children: [
            _SpeciesHeading(species: species, suitability: suitability),
            if (assignedTankName != null)
              SoftCard(
                child: Row(
                  children: [
                    const Icon(LucideIcons.network, color: AppColors.tealDark),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Assigned to $assignedTankName',
                        style: const TextStyle(
                          color: AppColors.text,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SectionHeader(
              title: 'Preferred water',
              subtitle: 'Reference ranges, not operational thresholds',
            ),
            SoftCard(
              child: Column(
                children: [
                  InfoRow(
                    label: 'Ideal temperature',
                    value: species.temperatureRange,
                    icon: LucideIcons.thermometer,
                  ),
                  const Divider(height: 1),
                  InfoRow(
                    label: 'Ideal pH',
                    value: species.phRange,
                    icon: LucideIcons.testTube,
                  ),
                  const Divider(height: 1),
                  InfoRow(
                    label: 'Ideal TDS',
                    value: species.tdsRange,
                    icon: LucideIcons.zap,
                  ),
                ],
              ),
            ),
            const SectionHeader(title: 'Care notes'),
            _TextInfoCard(
              icon: LucideIcons.utensils,
              title: 'Diet',
              text: species.diet,
            ),
            _TextInfoCard(
              icon: LucideIcons.heart,
              title: 'Care',
              text: species.careNote,
            ),
            _TextInfoCard(
              icon: LucideIcons.users,
              title: 'Compatibility',
              text: species.compatibilityNote,
            ),
          ],
        ),
      ),
    );
  }
}

class _SpeciesHeading extends StatelessWidget {
  const _SpeciesHeading({required this.species, required this.suitability});

  final FishSpecies species;
  final SpeciesSuitability? suitability;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const CircleAvatar(
                radius: 27,
                backgroundColor: AppColors.mint,
                child: Icon(
                  LucideIcons.fish,
                  color: AppColors.tealDark,
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      species.name,
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      species.scientificName,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          Text(
            species.description.isEmpty
                ? species.careNote
                : species.description,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 12,
              height: 1.4,
            ),
          ),
          if (suitability != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Text(
                  'Water suitability',
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                SpeciesSuitabilityBadge(suitability: suitability!),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _suitabilityMessage(suitability!),
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 11,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _suitabilityMessage(SpeciesSuitability suitability) {
  return switch (suitability) {
    SpeciesSuitability.suitable =>
      'Current temperature, pH, and TDS are within this species\' preferred range.',
    SpeciesSuitability.attention =>
      'One or more current readings are outside this species\' preferred range.',
    SpeciesSuitability.unavailable =>
      'Not enough current water data to evaluate suitability.',
  };
}

class _TextInfoCard extends StatelessWidget {
  const _TextInfoCard({
    required this.icon,
    required this.title,
    required this.text,
  });

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.tealDark, size: 20),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  text,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
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
    return InfoRow(label: label, value: value);
  }
}

class _AssignedContext extends StatelessWidget {
  const _AssignedContext({required this.tankName});

  final String tankName;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      child: Row(
        children: [
          const Icon(LucideIcons.network, color: AppColors.tealDark),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              'Assigned to $tankName',
              style: const TextStyle(
                color: AppColors.text,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FishFilters extends StatelessWidget {
  const _FishFilters({required this.selected, required this.onSelected});

  final FishFilter selected;
  final ValueChanged<FishFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _FishFilterChip(
            label: 'All',
            selected: selected == FishFilter.all,
            onTap: () => onSelected(FishFilter.all),
          ),
          const SizedBox(width: 8),
          _FishFilterChip(
            label: 'Freshwater',
            selected: selected == FishFilter.freshwater,
            onTap: () => onSelected(FishFilter.freshwater),
          ),
          const SizedBox(width: 8),
          _FishFilterChip(
            label: 'Saltwater',
            selected: selected == FishFilter.saltwater,
            onTap: () => onSelected(FishFilter.saltwater),
          ),
        ],
      ),
    );
  }
}

class _FishFilterChip extends StatelessWidget {
  const _FishFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      showCheckmark: false,
      selectedColor: AppColors.mint,
      backgroundColor: Colors.white,
      side: const BorderSide(color: AppColors.line),
      labelStyle: TextStyle(
        color: selected ? AppColors.tealDark : AppColors.text,
        fontSize: 11,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _TypeLabel extends StatelessWidget {
  const _TypeLabel({required this.type});

  final String type;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        type,
        style: const TextStyle(
          color: AppColors.tealDark,
          fontSize: 9,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

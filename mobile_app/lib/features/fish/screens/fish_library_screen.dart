import 'dart:async';

import 'package:aqualogic/app/theme/app_colors.dart';
import 'package:aqualogic/features/fish/data/mock_fish_repository.dart';
import 'package:aqualogic/features/fish/models/fish_species.dart';
import 'package:aqualogic/shared/network/api_failure.dart';
import 'package:aqualogic/shared/models/aqualogic_status.dart';
import 'package:aqualogic/shared/widgets/app_page.dart';
import 'package:aqualogic/features/more/widgets/more_header.dart';
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

class _FishLibraryScreenState extends State<FishLibraryScreen>
    with WidgetsBindingObserver {
  static const _foregroundRefreshInterval = Duration(minutes: 1);

  late final FishRepository _repository =
      widget.repository ?? const MockFishRepository();
  List<FishSpecies>? _species;
  ApiFailure? _initialFailure;
  ApiFailure? _refreshFailure;
  bool _loading = true;
  DateTime? _lastSuccessfulLoadAt;
  Future<void>? _loadInFlight;
  var _query = '';
  var _filter = FishFilter.all;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final lastSuccess = _lastSuccessfulLoadAt;
    if (_species == null ||
        lastSuccess == null ||
        DateTime.now().toUtc().difference(lastSuccess) >=
            _foregroundRefreshInterval) {
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _load() {
    final inFlight = _loadInFlight;
    if (inFlight != null) return inFlight;
    final request = _loadSpecies();
    _loadInFlight = request;
    return request.whenComplete(() {
      if (identical(_loadInFlight, request)) _loadInFlight = null;
    });
  }

  Future<void> _loadSpecies() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _initialFailure = null;
      });
    }
    try {
      final result = await _repository.list();
      if (!mounted) return;
      setState(() {
        _species = result;
        _lastSuccessfulLoadAt = DateTime.now().toUtc();
        _initialFailure = null;
        _refreshFailure = null;
      });
    } catch (error) {
      if (!mounted) return;
      final failure = error is ApiFailure
          ? error
          : const ApiFailure(
              kind: ApiFailureKind.unknown,
              message: 'Species could not be loaded. Try again.',
              retryable: true,
            );
      setState(() {
        if (_species == null) {
          _initialFailure = failure;
        } else {
          _refreshFailure = failure;
        }
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final species = _filteredSpecies();
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        top: false,
        child: AppPage(
          onRefresh: _load,
          header: MoreHeader(
            title: 'Fish species',
            subtitle: 'Practical care references for your tanks',
            onBack: () => Navigator.of(context).pop(),
            bottom: TextField(
              onChanged: (value) => setState(() => _query = value),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search species...',
                hintStyle: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 15,
                ),
                prefixIcon: const Icon(
                  LucideIcons.search,
                  color: AppColors.tealDark,
                ),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.94),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 13,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: AppColors.line),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: AppColors.line),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(
                    color: AppColors.tealDark,
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),
          children: [
            if (_species == null)
              _loading
                  ? const _SpeciesLoadingState()
                  : _SpeciesErrorState(
                      message:
                          _initialFailure?.message ??
                          'Check your connection and retry.',
                      retrying: _loading,
                      onRetry: () => unawaited(_load()),
                    )
            else ...[
              if (_refreshFailure != null)
                _SpeciesStaleState(
                  message: _refreshFailure!.message,
                  onRetry: () => unawaited(_load()),
                ),
              if (widget.assignedTankName != null)
                _AssignedContext(tankName: widget.assignedTankName!),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  const Text(
                    'Species directory',
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '${species.length} ${species.length == 1 ? 'species' : 'species'}',
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              if (_repository.supportsWaterTypeFilter)
                _FishFilters(
                  selected: _filter,
                  onSelected: (filter) => setState(() => _filter = filter),
                ),
              if (_species!.isEmpty)
                const EmptyState(
                  title: 'No species in the directory',
                  message: 'AquaLogic has no species records to show yet.',
                  icon: LucideIcons.fish,
                )
              else if (species.isEmpty)
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
          ],
        ),
      ),
    );
  }

  List<FishSpecies> _filteredSpecies() {
    final normalized = _query.trim().toLowerCase();
    return (_species ?? const <FishSpecies>[])
        .where((species) {
          final matchesQuery =
              normalized.isEmpty ||
              species.name.toLowerCase().contains(normalized) ||
              species.scientificName.toLowerCase().contains(normalized) ||
              species.type.toLowerCase().contains(normalized) ||
              species.careGroup.toLowerCase().contains(normalized) ||
              species.category.toLowerCase().contains(normalized);
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
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (species.type.isNotEmpty || species.category.isNotEmpty)
                      Flexible(
                        child: _TypeLabel(
                          type: species.type.isNotEmpty
                              ? species.type
                              : species.category,
                        ),
                      ),
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
                  _speciesSummary(species),
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
                          fontWeight: FontWeight.w600,
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

class SpeciesDetailScreen extends StatefulWidget {
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
  State<SpeciesDetailScreen> createState() => _SpeciesDetailScreenState();
}

class _SpeciesDetailScreenState extends State<SpeciesDetailScreen>
    with WidgetsBindingObserver {
  static const _foregroundRefreshInterval = Duration(minutes: 1);

  late FishRepository _repository;
  FishSpecies? _species;
  ApiFailure? _initialFailure;
  ApiFailure? _refreshFailure;
  bool _loading = true;
  DateTime? _lastSuccessfulLoadAt;
  Future<void>? _loadInFlight;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? const MockFishRepository();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant SpeciesDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.speciesId != widget.speciesId ||
        !identical(oldWidget.repository, widget.repository)) {
      _repository = widget.repository ?? const MockFishRepository();
      _species = null;
      unawaited(_load());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final lastSuccess = _lastSuccessfulLoadAt;
    if (_species == null ||
        lastSuccess == null ||
        DateTime.now().toUtc().difference(lastSuccess) >=
            _foregroundRefreshInterval) {
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _load() {
    final inFlight = _loadInFlight;
    if (inFlight != null) return inFlight;
    final request = _loadDetail();
    _loadInFlight = request;
    return request.whenComplete(() {
      if (identical(_loadInFlight, request)) _loadInFlight = null;
    });
  }

  Future<void> _loadDetail() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _initialFailure = null;
      });
    }
    try {
      final species = await _repository.findById(widget.speciesId);
      if (!mounted) return;
      if (species == null) {
        throw ApiFailure.fromStatus(404);
      }
      setState(() {
        _species = species;
        _lastSuccessfulLoadAt = DateTime.now().toUtc();
        _initialFailure = null;
        _refreshFailure = null;
      });
    } catch (error) {
      if (!mounted) return;
      final failure = error is ApiFailure
          ? error
          : const ApiFailure(
              kind: ApiFailureKind.unknown,
              message: 'Species details could not be loaded. Try again.',
              retryable: true,
            );
      setState(() {
        if (_species == null) {
          _initialFailure = failure;
        } else {
          _refreshFailure = failure;
        }
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final species = _species;
    if (species == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          top: false,
          child: AppPage(
            header: MoreHeader(
              title: 'Species detail',
              subtitle: 'Care reference from AquaLogic',
              onBack: () => Navigator.of(context).pop(),
            ),
            children: [
              if (_loading)
                const _SpeciesLoadingState(detail: true)
              else
                _SpeciesErrorState(
                  message:
                      _initialFailure?.message ??
                      'Species details are unavailable.',
                  retrying: _loading,
                  onRetry: () => unawaited(_load()),
                ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        top: false,
        child: AppPage(
          onRefresh: _load,
          header: MoreHeader(
            title: 'Species detail',
            subtitle: species.name,
            onBack: () => Navigator.of(context).pop(),
          ),
          children: [
            if (_refreshFailure != null)
              _SpeciesStaleState(
                message: _refreshFailure!.message,
                onRetry: () => unawaited(_load()),
              ),
            _SpeciesHeading(species: species, suitability: widget.suitability),
            if (widget.assignedTankName != null)
              SoftCard(
                child: Row(
                  children: [
                    const Icon(LucideIcons.network, color: AppColors.tealDark),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Assigned to ${widget.assignedTankName}',
                        style: const TextStyle(
                          color: AppColors.text,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
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
              text: species.careNote.isEmpty
                  ? 'No care guidance is provided for this species.'
                  : species.careNote,
            ),
            _TextInfoCard(
              icon: LucideIcons.users,
              title: 'Compatibility notes',
              text: species.compatibilityNote.isEmpty
                  ? 'No compatibility notes are provided for this species.'
                  : species.compatibilityNote,
            ),
          ],
        ),
      ),
    );
  }
}

String _speciesSummary(FishSpecies species) {
  if (species.careNote.isNotEmpty) return species.careNote;
  if (species.description.isNotEmpty) return species.description;
  return 'Care guidance is not provided.';
}

class _SpeciesLoadingState extends StatelessWidget {
  const _SpeciesLoadingState({this.detail = false});

  final bool detail;

  @override
  Widget build(BuildContext context) => SoftCard(
    child: Row(
      children: [
        const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            detail ? 'Loading species details…' : 'Loading species…',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );
}

class _SpeciesErrorState extends StatelessWidget {
  const _SpeciesErrorState({
    required this.message,
    required this.retrying,
    required this.onRetry,
  });

  final String message;
  final bool retrying;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => SoftCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(message, style: const TextStyle(color: AppColors.text)),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: retrying ? null : onRetry,
          icon: const Icon(LucideIcons.refreshCw, size: 16),
          label: const Text('Retry'),
        ),
      ],
    ),
  );
}

class _SpeciesStaleState extends StatelessWidget {
  const _SpeciesStaleState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => SoftCard(
    child: Row(
      children: [
        const Icon(LucideIcons.cloudOff, color: AppColors.offline),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            '$message Showing the last successful data.',
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ),
        IconButton(
          tooltip: 'Retry species refresh',
          onPressed: onRetry,
          icon: const Icon(LucideIcons.refreshCw),
        ),
      ],
    ),
  );
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
                        fontWeight: FontWeight.w700,
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
                ? species.careNote.isEmpty
                      ? 'No description is provided for this species.'
                      : species.careNote
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
                    fontWeight: FontWeight.w600,
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
                    fontWeight: FontWeight.w700,
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
                fontWeight: FontWeight.w600,
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
        fontWeight: FontWeight.w600,
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
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: AppColors.tealDark,
          fontSize: 9,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

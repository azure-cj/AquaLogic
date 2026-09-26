import 'package:aqualogic/features/fish/data/fish_api_models.dart';
import 'package:aqualogic/features/fish/data/mock_fish_repository.dart';
import 'package:aqualogic/features/fish/models/fish_species.dart';
import 'package:aqualogic/shared/network/api_client.dart';
import 'package:aqualogic/shared/network/api_failure.dart';

/// Read-only M5 integration for the authenticated FastAPI fish directory.
class ApiFishRepository implements FishRepository {
  ApiFishRepository({required this.apiClient});

  static const directoryPath = '/fish';

  final ApiClient apiClient;

  @override
  bool get isLiveData => true;

  @override
  bool get supportsWaterTypeFilter => false;

  @override
  Future<List<FishSpecies>> list() async {
    try {
      final response = await apiClient.get(directoryPath, authenticated: true);
      if (response.body is! List) {
        throw const FormatException('Expected species directory list.');
      }
      return (response.body as List)
          .map(FishSpeciesDto.fromJson)
          .map((species) => species.toDomain())
          .toList(growable: false);
    } on ApiFailure {
      rethrow;
    } on FormatException {
      throw _unreadable();
    }
  }

  @override
  Future<FishSpecies?> findById(String speciesId) async {
    final id = int.tryParse(speciesId);
    if (id == null || id <= 0) throw ApiFailure.fromStatus(404);
    try {
      final response = await apiClient.get('/fish/$id', authenticated: true);
      final dto = FishSpeciesDto.fromJson(response.body);
      if (dto.id != id) throw _unreadable();
      return dto.toDomain();
    } on ApiFailure {
      rethrow;
    } on FormatException {
      throw _unreadable();
    }
  }

  ApiFailure _unreadable() => const ApiFailure(
    kind: ApiFailureKind.unknown,
    message: 'AquaLogic returned unreadable species information.',
  );
}

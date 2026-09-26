import 'package:flutter/widgets.dart';

import 'package:aqualogic/features/fish/data/mock_fish_repository.dart';

/// App-composition scope for the shared species repository.
class FishRepositoryScope extends InheritedWidget {
  const FishRepositoryScope({
    super.key,
    required this.repository,
    required super.child,
  });

  final FishRepository repository;

  static FishRepository? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<FishRepositoryScope>()
      ?.repository;

  @override
  bool updateShouldNotify(FishRepositoryScope oldWidget) =>
      !identical(repository, oldWidget.repository);
}

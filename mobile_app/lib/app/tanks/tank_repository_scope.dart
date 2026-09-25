import 'package:flutter/widgets.dart';

import 'package:aqualogic/features/tanks/data/mock_tank_repository.dart';

/// App-composition scope for the shared Tank repository.
class TankRepositoryScope extends InheritedWidget {
  const TankRepositoryScope({
    super.key,
    required this.repository,
    required super.child,
  });

  final TankRepository repository;

  static TankRepository? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<TankRepositoryScope>()
      ?.repository;

  @override
  bool updateShouldNotify(TankRepositoryScope oldWidget) =>
      !identical(repository, oldWidget.repository);
}

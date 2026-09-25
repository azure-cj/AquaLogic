import 'package:flutter/widgets.dart';

import 'package:aqualogic/features/home/data/home_repository.dart';

/// App-composition scope for the Home repository, parallel to [AuthScope].
class HomeRepositoryScope extends InheritedWidget {
  const HomeRepositoryScope({
    super.key,
    required this.repository,
    required super.child,
  });

  final HomeRepository repository;

  static HomeRepository? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<HomeRepositoryScope>()
      ?.repository;

  @override
  bool updateShouldNotify(HomeRepositoryScope oldWidget) =>
      !identical(repository, oldWidget.repository);
}

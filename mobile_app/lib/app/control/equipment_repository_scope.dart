import 'package:flutter/widgets.dart';

import 'package:aqualogic/features/control/data/mock_equipment_repository.dart';

/// App-composition scope for the shared equipment repository.
class EquipmentRepositoryScope extends InheritedWidget {
  const EquipmentRepositoryScope({
    super.key,
    required this.repository,
    required super.child,
  });

  final EquipmentRepository repository;

  static EquipmentRepository? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<EquipmentRepositoryScope>()
      ?.repository;

  @override
  bool updateShouldNotify(EquipmentRepositoryScope oldWidget) =>
      !identical(repository, oldWidget.repository);
}

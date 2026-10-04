import 'package:flutter/widgets.dart';
import 'package:aqualogic/features/console/data/console_repository.dart';
import 'package:aqualogic/features/console/data/mock_console_repository.dart';

typedef ConsoleRepositoryFactory = ConsoleRepository Function();
ConsoleRepository createPrototypeConsoleRepository() => MockConsoleRepository();

/// Composition only: routes receive their own repository, independent of auth/API.
class ConsoleRepositoryScope extends InheritedWidget {
  const ConsoleRepositoryScope({
    super.key,
    required this.createRepository,
    required this.onActiveChanged,
    required super.child,
  });
  final ConsoleRepositoryFactory createRepository;
  final ValueChanged<bool> onActiveChanged;
  static ConsoleRepositoryScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ConsoleRepositoryScope>();
  @override
  bool updateShouldNotify(ConsoleRepositoryScope oldWidget) =>
      createRepository != oldWidget.createRepository;
}

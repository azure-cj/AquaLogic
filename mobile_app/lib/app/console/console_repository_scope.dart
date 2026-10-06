import 'package:flutter/widgets.dart';
import 'package:aqualogic/features/console/data/console_repository.dart';
import 'package:aqualogic/features/console/data/mock_console_repository.dart';
import 'package:aqualogic/features/console/data/esp32_console_repository.dart';

typedef ConsoleRepositoryFactory = ConsoleRepository Function();
ConsoleRepository createPrototypeConsoleRepository() => MockConsoleRepository();
ConsoleRepository createLiveConsoleRepository() => Esp32ConsoleRepository();

/// Composition only: routes receive their own repository, independent of auth/API.
class ConsoleRepositoryScope extends InheritedWidget {
  const ConsoleRepositoryScope({
    super.key,
    required this.createRepository,
    required this.onActiveChanged,
    required super.child,
    this.liveMode = false,
  });
  final ConsoleRepositoryFactory createRepository;
  final ValueChanged<bool> onActiveChanged;
  final bool liveMode;
  static ConsoleRepositoryScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ConsoleRepositoryScope>();
  @override
  bool updateShouldNotify(ConsoleRepositoryScope oldWidget) =>
      createRepository != oldWidget.createRepository ||
      liveMode != oldWidget.liveMode;
}

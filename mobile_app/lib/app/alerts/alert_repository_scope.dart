import 'package:flutter/widgets.dart';

import 'package:aqualogic/features/alerts/data/mock_alert_repository.dart';

/// App-composition scope for the shared Alerts/Monitoring repository.
class AlertRepositoryScope extends InheritedWidget {
  const AlertRepositoryScope({
    super.key,
    required this.repository,
    required super.child,
  });

  final AlertRepository repository;

  static AlertRepository? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<AlertRepositoryScope>()
      ?.repository;

  @override
  bool updateShouldNotify(AlertRepositoryScope oldWidget) =>
      !identical(repository, oldWidget.repository);
}

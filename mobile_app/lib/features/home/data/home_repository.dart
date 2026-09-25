import 'package:aqualogic/features/home/models/home_dashboard_data.dart';

/// Asynchronous boundary for the Home dashboard.
///
/// Production and demo implementations keep the same domain contract. Only
/// the demo repository opts into the shell's mock-data ticker.
abstract class HomeRepository {
  const HomeRepository();

  bool get isLiveData => false;

  bool get refreshDemoData => false;

  Future<HomeDashboardData> load();
}

import 'package:aqualogic/shared/models/aqualogic_status.dart';

enum HomeOperationalStatus {
  normal,
  warning,
  critical,
  offline;

  String get label => switch (this) {
    HomeOperationalStatus.normal => 'Normal',
    HomeOperationalStatus.warning => 'Warning',
    HomeOperationalStatus.critical => 'Critical',
    HomeOperationalStatus.offline => 'Offline',
  };

  int get priority => switch (this) {
    HomeOperationalStatus.critical => 0,
    HomeOperationalStatus.warning => 1,
    HomeOperationalStatus.offline => 2,
    HomeOperationalStatus.normal => 3,
  };

  bool get requiresAttention => this != HomeOperationalStatus.normal;

  OperationalStatus get asOperationalStatus => switch (this) {
    HomeOperationalStatus.normal => OperationalStatus.normal,
    HomeOperationalStatus.warning => OperationalStatus.warning,
    HomeOperationalStatus.critical => OperationalStatus.critical,
    HomeOperationalStatus.offline => OperationalStatus.offline,
  };
}

enum HomeAttentionType { waterQuality, monitoring }

enum HomeActivityType { feeding, uvCycle }

class HomeTankSummary {
  const HomeTankSummary({
    required this.id,
    required this.initial,
    required this.name,
    required this.subtitle,
    required this.status,
    required this.lastReportLabel,
    required this.contextLabel,
    this.lastReportedAt,
  });

  final String id;
  final String initial;
  final String name;
  final String subtitle;
  final HomeOperationalStatus status;
  final DateTime? lastReportedAt;
  final String lastReportLabel;
  final String contextLabel;
}

class HomeAttentionItem {
  const HomeAttentionItem({
    required this.id,
    required this.tankId,
    required this.tankName,
    required this.type,
    required this.status,
    required this.title,
    required this.message,
    required this.actionLabel,
    this.sourceId,
  });

  final String id;
  final String tankId;
  final String tankName;
  final HomeAttentionType type;
  final HomeOperationalStatus status;
  final String title;
  final String message;
  final String actionLabel;
  final String? sourceId;
}

class HomeMonitoringSummary {
  const HomeMonitoringSummary({
    required this.totalTankCount,
    required this.reportingTankCount,
    required this.outageCount,
    required this.sensorFeedOnline,
  });

  final int totalTankCount;
  final int reportingTankCount;
  final int outageCount;
  final bool sensorFeedOnline;
}

class HomeActivityItem {
  const HomeActivityItem({
    required this.id,
    required this.title,
    required this.tankName,
    required this.timeLabel,
    required this.type,
    this.occurredAt,
  });

  final String id;
  final String title;
  final String tankName;
  final String timeLabel;
  final HomeActivityType type;
  final DateTime? occurredAt;
}

class HomeDashboardData {
  const HomeDashboardData({
    required this.tanks,
    required this.attentionItems,
    required this.monitoring,
    required this.recentActivity,
  });

  final List<HomeTankSummary> tanks;
  final List<HomeAttentionItem> attentionItems;
  final HomeMonitoringSummary monitoring;
  final List<HomeActivityItem> recentActivity;

  int get normalTankCount => _count(HomeOperationalStatus.normal);

  int get needsAttentionCount => tanks
      .where(
        (tank) =>
            tank.status == HomeOperationalStatus.warning ||
            tank.status == HomeOperationalStatus.critical,
      )
      .length;

  int get offlineTankCount => _count(HomeOperationalStatus.offline);

  bool get allTanksNormal =>
      tanks.isNotEmpty && normalTankCount == tanks.length;

  int _count(HomeOperationalStatus status) {
    return tanks.where((tank) => tank.status == status).length;
  }
}

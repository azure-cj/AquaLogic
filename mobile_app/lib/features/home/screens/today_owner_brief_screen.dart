import 'package:aqualogic/features/alerts/data/build_alerts.dart';
import 'package:aqualogic/features/alerts/models/alert_info.dart';
import 'package:aqualogic/features/demo/demo_data.dart';
import 'package:aqualogic/features/sensors/models/sensor_snapshot.dart';
import 'package:aqualogic/features/tanks/models/tank_info.dart';
import 'package:aqualogic/features/tanks/models/tank_status.dart';
import 'package:aqualogic/shared/models/reading_state.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class TodayOwnerBriefScreen extends StatelessWidget {
  const TodayOwnerBriefScreen({
    super.key,
    required this.snapshot,
    required this.onBackToHome,
  });

  final SensorSnapshot snapshot;
  final VoidCallback onBackToHome;

  static const _pageBackground = Color(0xFF031117);
  static const _oceanDeep = Color(0xFF005E7A);
  static const _oceanTeal = Color(0xFF008C95);
  static const _oceanAqua = Color(0xFF13B8C8);
  static const _ink = Colors.white;
  static const _mutedInk = Color(0xFFD9FFF2);
  static const _softInk = Color(0xFFB9E8ED);

  @override
  Widget build(BuildContext context) {
    final alerts = buildAlerts(snapshot);
    final topAlert = alerts.first;
    final highestRiskTank = DemoData.tanks.reduce(
      (current, next) => next.health < current.health ? next : current,
    );
    final warningCount = _countTanks(ReadingState.warning);
    final criticalCount = _countTanks(ReadingState.critical);
    final watchCount = warningCount + criticalCount;
    final isCalm =
        snapshot.overallState == ReadingState.normal && watchCount == 0;
    final summary = isCalm
        ? 'All systems are looking calm.'
        : '${highestRiskTank.name} needs attention.';

    return Scaffold(
      backgroundColor: _pageBackground,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 18, 0, 10),
                child: _ReportCard(
                  dateLabel: _dateLabel(DateTime.now()),
                  healthPercent: snapshot.healthPercent,
                  summary: summary,
                  topAlert: topAlert,
                  highestRiskTank: highestRiskTank,
                  watchCount: watchCount,
                ),
              ),
            ),
            _SideBackButton(onTap: onBackToHome),
          ],
        ),
      ),
    );
  }

  int _countTanks(ReadingState state) {
    return DemoData.tanks
        .where((tank) => tankStatusState(tank.status) == state)
        .length;
  }

  String _dateLabel(DateTime date) {
    const weekdays = [
      'MONDAY',
      'TUESDAY',
      'WEDNESDAY',
      'THURSDAY',
      'FRIDAY',
      'SATURDAY',
      'SUNDAY',
    ];
    const months = [
      'JANUARY',
      'FEBRUARY',
      'MARCH',
      'APRIL',
      'MAY',
      'JUNE',
      'JULY',
      'AUGUST',
      'SEPTEMBER',
      'OCTOBER',
      'NOVEMBER',
      'DECEMBER',
    ];

    return '${weekdays[date.weekday - 1]}, ${months[date.month - 1]} ${date.day}';
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.dateLabel,
    required this.healthPercent,
    required this.summary,
    required this.topAlert,
    required this.highestRiskTank,
    required this.watchCount,
  });

  final String dateLabel;
  final int healthPercent;
  final String summary;
  final AlertInfo topAlert;
  final TankInfo highestRiskTank;
  final int watchCount;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 760;
        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 14),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Container(
              margin: const EdgeInsets.only(right: 22),
              padding: EdgeInsets.fromLTRB(24, compact ? 26 : 34, 24, 26),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    TodayOwnerBriefScreen._oceanDeep,
                    TodayOwnerBriefScreen._oceanTeal,
                    TodayOwnerBriefScreen._oceanAqua,
                  ],
                ),
                borderRadius: BorderRadius.only(
                  topRight: Radius.circular(42),
                  bottomRight: Radius.circular(42),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dateLabel,
                    style: const TextStyle(
                      color: TodayOwnerBriefScreen._mutedInk,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 3,
                    ),
                  ),
                  SizedBox(height: compact ? 26 : 42),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          'Good morning, JRed.\nYour aquariums are $healthPercent% healthy today.',
                          style: const TextStyle(
                            color: TodayOwnerBriefScreen._ink,
                            fontSize: 34,
                            fontWeight: FontWeight.w900,
                            height: 1.08,
                            letterSpacing: 0,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const _LogoMark(),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    summary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: TodayOwnerBriefScreen._mutedInk,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                  SizedBox(height: compact ? 58 : 120),
                  const Text(
                    'Today',
                    style: TextStyle(
                      color: TodayOwnerBriefScreen._ink,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 18),
                  _TimelineEntry(
                    number: '01',
                    title: topAlert.title,
                    detail: topAlert.recommendation,
                  ),
                  _TimelineEntry(
                    number: '02',
                    title: 'Feeding completed',
                    detail: 'Auto-feed cycle finished successfully.',
                  ),
                  _TimelineEntry(
                    number: '03',
                    title: 'UV cycle complete',
                    detail: 'Sterilization ran for 45 minutes.',
                  ),
                  _TimelineEntry(
                    number: '04',
                    title: highestRiskTank.name,
                    detail: '${highestRiskTank.health}% health today',
                  ),
                  SizedBox(height: compact ? 38 : 74),
                  Divider(
                    color: Colors.white.withValues(alpha: 0.18),
                    height: 1,
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(
                        child: _BottomStat(
                          label: 'HEALTH',
                          value: '$healthPercent%',
                        ),
                      ),
                      Expanded(
                        child: _BottomStat(
                          label: 'WATCH',
                          value: '$watchCount',
                        ),
                      ),
                      Expanded(
                        child: _BottomStat(
                          label: 'RISK',
                          value: highestRiskTank.name,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: compact ? 46 : 90),
                  const Center(child: _FooterBrand()),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LogoMark extends StatelessWidget {
  const _LogoMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Padding(
        padding: const EdgeInsets.all(9),
        child: Image.asset(
          'assets/images/aqualogic_icon.png',
          fit: BoxFit.contain,
          semanticLabel: 'AquaLogic',
        ),
      ),
    );
  }
}

class _TimelineEntry extends StatelessWidget {
  const _TimelineEntry({
    required this.number,
    required this.title,
    required this.detail,
  });

  final String number;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 34,
            child: Text(
              number,
              style: const TextStyle(
                color: TodayOwnerBriefScreen._ink,
                fontSize: 13,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: TodayOwnerBriefScreen._ink,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: TodayOwnerBriefScreen._mutedInk,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomStat extends StatelessWidget {
  const _BottomStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: TodayOwnerBriefScreen._softInk,
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: TodayOwnerBriefScreen._ink,
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _FooterBrand extends StatelessWidget {
  const _FooterBrand();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          'assets/images/aqualogic_icon.png',
          width: 36,
          height: 36,
          semanticLabel: 'AquaLogic',
        ),
        const SizedBox(width: 10),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'AquaLogic',
              style: TextStyle(
                color: TodayOwnerBriefScreen._ink,
                fontSize: 15,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
            Text(
              'Owner brief',
              style: TextStyle(
                color: TodayOwnerBriefScreen._mutedInk,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SideBackButton extends StatelessWidget {
  const _SideBackButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 0,
      top: 0,
      bottom: 0,
      child: Center(
        child: Semantics(
          button: true,
          label: 'Back to Home',
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(22),
              ),
              onTap: onTap,
              child: Tooltip(
                message: 'Back to Home',
                child: Container(
                  width: 52,
                  height: 116,
                  decoration: BoxDecoration(
                    color: const Color(0xFF062631).withValues(alpha: 0.94),
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(22),
                    ),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                  child: const Icon(
                    LucideIcons.chevronRight,
                    color: Colors.white,
                    size: 34,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

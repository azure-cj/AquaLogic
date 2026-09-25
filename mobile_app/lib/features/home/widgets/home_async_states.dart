import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:aqualogic/app/theme/app_colors.dart';
import 'package:aqualogic/app/theme/app_tokens.dart';
import 'package:aqualogic/shared/widgets/soft_card.dart';

class HomeLoadingContent extends StatelessWidget {
  const HomeLoadingContent({super.key});

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      key: const ValueKey('home-loading-content'),
      label: 'Loading live Home data',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SoftCard(
            child: Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.tealDark,
                    value: reduceMotion ? 0.65 : null,
                  ),
                ),
                const SizedBox(width: 11),
                const Expanded(
                  child: Text(
                    'Loading live Home data',
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sectionGap),
          const _HomePlaceholderCard(height: 106),
          const SizedBox(height: AppSpacing.sectionGap),
          const _HomePlaceholderCard(height: 136),
        ],
      ),
    );
  }
}

class HomeErrorCard extends StatelessWidget {
  const HomeErrorCard({
    super.key,
    required this.message,
    required this.onRetry,
    this.retrying = false,
  });

  final String message;
  final VoidCallback onRetry;
  final bool retrying;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return SoftCard(
      child: Column(
        key: const ValueKey('home-load-error'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(LucideIcons.wifiOff, color: AppColors.offline, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Couldn't load Home from AquaLogic",
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '$message Tank/device status has not been changed by this phone connection failure.',
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 12,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              key: const ValueKey('home-load-retry'),
              onPressed: retrying ? null : onRetry,
              icon: retrying
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        value: reduceMotion ? 0.65 : null,
                      ),
                    )
                  : const Icon(LucideIcons.refreshCw, size: 16),
              label: Text(retrying ? 'Retrying' : 'Retry'),
              style: TextButton.styleFrom(foregroundColor: AppColors.tealDark),
            ),
          ),
        ],
      ),
    );
  }
}

class HomePartialFailureCard extends StatelessWidget {
  const HomePartialFailureCard({
    super.key,
    required this.alertsAvailable,
    required this.monitoringAvailable,
    required this.onRetry,
  });

  final bool alertsAvailable;
  final bool monitoringAvailable;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final message = switch ((alertsAvailable, monitoringAvailable)) {
      (false, false) =>
        'Alert and monitoring details could not be loaded. Fleet data is still live.',
      (false, true) =>
        'Water-quality alert details could not be loaded. Fleet and monitoring data are still live.',
      (true, false) =>
        'Monitoring incident details could not be loaded. Fleet outage counts are still shown.',
      (true, true) => '',
    };
    return SoftCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            LucideIcons.circleAlert,
            color: AppColors.warning,
            size: 19,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    key: const ValueKey('home-partial-retry'),
                    onPressed: onRetry,
                    child: const Text('Retry'),
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

class HomeStaleDataCard extends StatelessWidget {
  const HomeStaleDataCard({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(LucideIcons.wifiOff, color: AppColors.offline, size: 19),
          const SizedBox(width: 9),
          const Expanded(
            child: Text(
              "Couldn't refresh from AquaLogic. The figures below are the last successfully loaded Home data and may be out of date.",
              style: TextStyle(
                color: AppColors.text,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(width: 4),
          TextButton(
            key: const ValueKey('home-stale-retry'),
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class _HomePlaceholderCard extends StatelessWidget {
  const _HomePlaceholderCard({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      child: SizedBox(
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              height: 12,
              width: 142,
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              height: 9,
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.background.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(5),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              height: 9,
              width: 188,
              decoration: BoxDecoration(
                color: AppColors.background.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:aqualogic/app/theme/app_colors.dart';
import 'package:aqualogic/app/theme/app_tokens.dart';
import 'package:aqualogic/features/alerts/data/alert_mutation_service.dart';
import 'package:aqualogic/features/alerts/data/mock_alert_repository.dart';
import 'package:aqualogic/features/alerts/models/alert_info.dart';
import 'package:aqualogic/features/alerts/screens/alert_detail_screen.dart';
import 'package:aqualogic/features/alerts/widgets/alert_tile.dart';
import 'package:aqualogic/features/alerts/widgets/alerts_header.dart';
import 'package:aqualogic/features/sensors/models/sensor_snapshot.dart';
import 'package:aqualogic/shared/widgets/app_page.dart';
import 'package:aqualogic/shared/widgets/semantic_status_widgets.dart';
import 'package:aqualogic/shared/network/api_failure.dart';
import 'package:aqualogic/shared/formatters/local_timestamps.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

enum AlertStream { waterQuality, monitoring }

enum AlertView { active, history }

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({
    super.key,
    required this.snapshot,
    this.repository,
    this.initialReferenceId,
    this.initialStream = AlertStream.waterQuality,
    this.initialView = AlertView.active,
    this.onAlertResolved,
    this.refreshTrigger = 0,
  });

  final SensorSnapshot snapshot;
  final AlertRepository? repository;
  final String? initialReferenceId;
  final AlertStream initialStream;
  final AlertView initialView;
  final ValueChanged<AlertInfo>? onAlertResolved;
  final int refreshTrigger;

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen>
    with WidgetsBindingObserver {
  static const _foregroundRefreshInterval = Duration(minutes: 1);

  late AlertRepository _repository =
      widget.repository ?? const MockAlertRepository();
  final _waterActive = _AlertCollection<AlertInfo>();
  final _waterHistory = _AlertCollection<AlertInfo>();
  final _monitoringActive = _AlertCollection<MonitoringIncident>();
  final _monitoringHistory = _AlertCollection<MonitoringIncident>();
  final _resolvedAlertOverlay = <String, AlertInfo>{};
  late AlertStream _stream;
  late AlertView _view;
  var _didResolveInitialReference = false;
  String? _focusedMonitoringId;
  String? _referenceMessage;
  String? _resolvingAlertId;
  DateTime? _lastSuccessfulLoadAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _stream = widget.initialStream;
    _view = widget.initialView;
    unawaited(_loadInitial());
  }

  @override
  void didUpdateWidget(covariant AlertsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sourceChanged =
        oldWidget.snapshot != widget.snapshot ||
        oldWidget.repository != widget.repository ||
        oldWidget.initialReferenceId != widget.initialReferenceId ||
        oldWidget.initialStream != widget.initialStream ||
        oldWidget.initialView != widget.initialView;
    if (sourceChanged) {
      _repository = widget.repository ?? const MockAlertRepository();
      _stream = widget.initialStream;
      _view = widget.initialView;
      _didResolveInitialReference = false;
      _referenceMessage = null;
      _clearCollections();
      unawaited(_loadInitial());
    } else if (oldWidget.refreshTrigger != widget.refreshTrigger) {
      // A detail opened from Home or Tank Detail can resolve an alert without
      // going through this tab's local mutation handler. Refresh the cached
      // Incident Center lists while preserving the selected stream and view.
      unawaited(_refreshLoaded());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final lastSuccess = _lastSuccessfulLoadAt;
    if (lastSuccess == null ||
        DateTime.now().toUtc().difference(lastSuccess) >=
            _foregroundRefreshInterval) {
      unawaited(_refreshLoaded());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _loadInitial() async {
    final requests = <Future<void>>[
      _loadWaterQuality(history: false),
      _loadMonitoring(history: false),
    ];
    if (widget.initialView == AlertView.history) {
      requests.add(
        widget.initialStream == AlertStream.waterQuality
            ? _loadWaterQuality(history: true)
            : _loadMonitoring(history: true),
      );
    }
    await Future.wait(requests);
    if (widget.initialReferenceId != null && !_didResolveInitialReference) {
      await _resolveInitialReference();
    }
  }

  void _clearCollections() {
    _waterActive.reset();
    _waterHistory.reset();
    _monitoringActive.reset();
    _monitoringHistory.reset();
  }

  Future<void> _loadWaterQuality({required bool history}) async {
    final collection = history ? _waterHistory : _waterActive;
    if (collection.loading || collection.refreshing) return;
    setState(() {
      collection.loading = !collection.loaded;
      collection.refreshing = collection.loaded;
      collection.failure = null;
    });
    try {
      final loadedAlerts = await _repository.loadWaterQualityAlerts(
        snapshot: widget.snapshot,
        history: history,
      );
      final alerts = history
          ? _mergeHistoryAlerts(loadedAlerts)
          : loadedAlerts
                .where((alert) => !_resolvedAlertOverlay.containsKey(alert.id))
                .toList(growable: false);
      if (!mounted) return;
      setState(() {
        collection.items = alerts;
        collection.total = alerts.length;
        collection.loaded = true;
        collection.failure = null;
        collection.lastLoadedAt = DateTime.now().toUtc();
        _lastSuccessfulLoadAt = collection.lastLoadedAt;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => collection.failure = _safeFailure(error));
    } finally {
      if (mounted) {
        setState(() {
          collection.loading = false;
          collection.refreshing = false;
        });
      }
    }
  }

  Future<void> _loadMonitoring({
    required bool history,
    bool loadNextPage = false,
  }) async {
    final collection = history ? _monitoringHistory : _monitoringActive;
    if (collection.loading || collection.refreshing || collection.loadingMore) {
      return;
    }
    final pageNumber = loadNextPage ? collection.page + 1 : 1;
    setState(() {
      if (loadNextPage) {
        collection.loadingMore = true;
        collection.nextPageFailure = null;
      } else {
        collection.loading = !collection.loaded;
        collection.refreshing = collection.loaded;
        collection.failure = null;
      }
    });
    try {
      final result = await _repository.loadMonitoringIncidents(
        snapshot: widget.snapshot,
        history: history,
        page: pageNumber,
      );
      if (!mounted) return;
      if (result.page != pageNumber) {
        throw const FormatException('Monitoring page did not match request.');
      }
      setState(() {
        if (loadNextPage) {
          final ids = collection.items.map((item) => item.id).toSet();
          collection.items = [
            ...collection.items,
            ...result.items.where((item) => ids.add(item.id)),
          ];
        } else {
          collection.items = result.items;
        }
        collection.page = result.page;
        collection.pageSize = result.pageSize;
        collection.total = result.total;
        collection.hasNext = result.hasNext;
        collection.loaded = true;
        collection.failure = null;
        collection.nextPageFailure = null;
        collection.lastLoadedAt = DateTime.now().toUtc();
        _lastSuccessfulLoadAt = collection.lastLoadedAt;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        if (loadNextPage) {
          collection.nextPageFailure = _safeFailure(error);
        } else {
          collection.failure = _safeFailure(error);
        }
      });
    } finally {
      if (mounted) {
        setState(() {
          collection.loading = false;
          collection.refreshing = false;
          collection.loadingMore = false;
        });
      }
    }
  }

  Future<void> _refreshLoaded() async {
    final requests = <Future<void>>[
      _loadWaterQuality(history: false),
      _loadMonitoring(history: false),
    ];
    if (_waterHistory.loaded ||
        _view == AlertView.history && _stream == AlertStream.waterQuality) {
      requests.add(_loadWaterQuality(history: true));
    }
    if (_monitoringHistory.loaded ||
        _view == AlertView.history && _stream == AlertStream.monitoring) {
      requests.add(_loadMonitoring(history: true));
    }
    await Future.wait(requests);
  }

  Future<void> _retryCurrent() => _stream == AlertStream.waterQuality
      ? _loadWaterQuality(history: _view == AlertView.history)
      : _loadMonitoring(history: _view == AlertView.history);

  void _selectStream(AlertStream stream) {
    setState(() => _stream = stream);
    if (stream == AlertStream.waterQuality && _view == AlertView.history) {
      unawaited(_loadWaterQuality(history: true));
    } else if (stream == AlertStream.monitoring && _view == AlertView.history) {
      unawaited(_loadMonitoring(history: true));
    }
  }

  void _selectView(AlertView view) {
    setState(() => _view = view);
    if (_stream == AlertStream.waterQuality) {
      unawaited(_loadWaterQuality(history: view == AlertView.history));
    } else {
      unawaited(_loadMonitoring(history: view == AlertView.history));
    }
  }

  @override
  Widget build(BuildContext context) {
    final water = _view == AlertView.active ? _waterActive : _waterHistory;
    final monitoring = _view == AlertView.active
        ? _monitoringActive
        : _monitoringHistory;
    final activeWaterCount = _waterActive.loaded ? _waterActive.total : null;
    final activeMonitoringCount = _monitoringActive.loaded
        ? _monitoringActive.total
        : null;
    final criticalCount = _waterActive.loaded
        ? _waterActive.items
              .where((alert) => alert.severity == AlertSeverity.critical)
              .length
        : null;
    final warningCount = _waterActive.loaded
        ? _waterActive.items
              .where((alert) => alert.severity == AlertSeverity.warning)
              .length
        : null;

    return Scaffold(
      // Alerts is rendered both inside the authenticated shell and as a
      // standalone exact-context route. Keep the page's Material surface
      // local so the latter does not fall back to Flutter's red/yellow
      // missing-Material diagnostic text style or a black route background.
      backgroundColor: AppColors.background,
      body: AppPage(
        bottomClearance: AppSpacing.bottomDockClearance,
        header: const AlertsHeader(
          title: 'Alerts',
          subtitle: 'Operational issues across your fleet',
        ),
        onRefresh: _refreshLoaded,
        children: [
          _AlertSummary(
            criticalCount: criticalCount,
            warningCount: warningCount,
            monitoringCount: activeMonitoringCount,
          ),
          if (_hasSourceFailureOutsideCurrentSelection)
            _SourceFailureNotice(
              message: _otherSourceFailureMessage,
              onRetry: _refreshLoaded,
            ),
          if (_referenceMessage != null)
            Semantics(
              liveRegion: true,
              child: Text(
                _referenceMessage!,
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          _AlertStreamSelector(
            selected: _stream,
            waterQualityCount: activeWaterCount,
            monitoringCount: activeMonitoringCount,
            onSelected: _selectStream,
          ),
          _AlertStateTabs(selected: _view, onSelected: _selectView),
          if (_stream == AlertStream.waterQuality)
            _WaterQualityList(
              alerts: water.items,
              loading: water.loading,
              refreshing: water.refreshing,
              loaded: water.loaded,
              failure: water.failure,
              showHistory: _view == AlertView.history,
              onOpen: _openAlert,
              onMarkHandled: _confirmMarkHandled,
              resolvingAlertId: _resolvingAlertId,
              onRetry: _retryCurrent,
            )
          else
            _MonitoringList(
              incidents: monitoring.items,
              loading: monitoring.loading,
              refreshing: monitoring.refreshing,
              loaded: monitoring.loaded,
              failure: monitoring.failure,
              showHistory: _view == AlertView.history,
              focusedId: _focusedMonitoringId,
              onOpen: _openMonitoring,
              hasNext: monitoring.hasNext,
              loadingMore: monitoring.loadingMore,
              nextPageFailure: monitoring.nextPageFailure,
              onLoadMore: () => _loadMonitoring(
                history: _view == AlertView.history,
                loadNextPage: true,
              ),
              onRetry: _retryCurrent,
              onRetryNext: () => _loadMonitoring(
                history: _view == AlertView.history,
                loadNextPage: true,
              ),
            ),
        ],
      ),
    );
  }

  bool get _hasSourceFailureOutsideCurrentSelection =>
      _stream == AlertStream.waterQuality
      ? _monitoringActive.failure != null
      : _waterActive.failure != null;

  String get _otherSourceFailureMessage => _stream == AlertStream.waterQuality
      ? 'Monitoring data could not be loaded. Water-quality alerts remain available.'
      : 'Water-quality alert data could not be loaded. Monitoring remains available.';

  Future<void> _resolveInitialReference() async {
    final referenceId = widget.initialReferenceId;
    if (!mounted || referenceId == null || _didResolveInitialReference) return;
    _didResolveInitialReference = true;
    if (widget.initialStream == AlertStream.waterQuality) {
      var alert = _firstOrNull(
        _waterActive.items.where((item) => item.id == referenceId),
      );
      if (alert == null) {
        setState(() {
          _stream = AlertStream.waterQuality;
          _view = AlertView.history;
        });
        await _loadWaterQuality(history: true);
        alert = _firstOrNull(
          _waterHistory.items.where((item) => item.id == referenceId),
        );
      }
      if (!mounted) return;
      final foundAlert = alert;
      if (foundAlert != null) {
        setState(() {
          _stream = AlertStream.waterQuality;
          _view = foundAlert.isActive ? AlertView.active : AlertView.history;
        });
        await _openAlert(foundAlert);
        return;
      }
    } else {
      var incident = await _findMonitoringReference(
        referenceId,
        history: false,
      );
      var history = false;
      if (incident == null) {
        history = true;
        incident = await _findMonitoringReference(referenceId, history: true);
      }
      if (!mounted) return;
      final foundIncident = incident;
      if (foundIncident != null) {
        setState(() {
          _stream = AlertStream.monitoring;
          _view = history ? AlertView.history : AlertView.active;
          _focusedMonitoringId = foundIncident.id;
        });
        _showMonitoringDetails(foundIncident);
        return;
      }
    }

    if (!mounted) return;
    final unavailableView = _viewWithReferenceLoadFailure(widget.initialStream);
    if (unavailableView != null) {
      // A failed list read cannot establish that the referenced record is
      // missing. Leave the user on the failed source so its retry state stays
      // visible instead of presenting a false not-found message.
      setState(() {
        _stream = widget.initialStream;
        _view = unavailableView;
      });
      return;
    }
    setState(() {
      _referenceMessage = widget.initialStream == AlertStream.monitoring
          ? 'This monitoring incident is no longer available.'
          : 'This alert is no longer available.';
    });
  }

  AlertView? _viewWithReferenceLoadFailure(AlertStream stream) {
    if (stream == AlertStream.waterQuality) {
      if (_waterActive.failure != null) return AlertView.active;
      if (_waterHistory.failure != null) return AlertView.history;
      return null;
    }
    if (_monitoringActive.failure != null ||
        _monitoringActive.nextPageFailure != null) {
      return AlertView.active;
    }
    if (_monitoringHistory.failure != null ||
        _monitoringHistory.nextPageFailure != null) {
      return AlertView.history;
    }
    return null;
  }

  Future<MonitoringIncident?> _findMonitoringReference(
    String id, {
    required bool history,
  }) async {
    final collection = history ? _monitoringHistory : _monitoringActive;
    if (!collection.loaded) await _loadMonitoring(history: history);
    var found = _firstOrNull(collection.items.where((item) => item.id == id));
    while (found == null && collection.hasNext) {
      await _loadMonitoring(history: history, loadNextPage: true);
      found = _firstOrNull(collection.items.where((item) => item.id == id));
      if (collection.nextPageFailure != null) return null;
    }
    return _firstOrNull(collection.items.where((item) => item.id == id));
  }

  Future<void> _confirmMarkHandled(AlertInfo alert) async {
    final shouldMark = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark this alert as handled?'),
        content: const Text(
          'This removes it from active alerts. It does not confirm that the water condition has returned to normal.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Mark handled'),
          ),
        ],
      ),
    );
    if (!mounted || shouldMark != true) return;
    setState(() => _resolvingAlertId = alert.id);
    final outcome = await markAlertHandled(
      repository: _repository,
      snapshot: widget.snapshot,
      alert: alert,
    );
    if (!mounted) return;
    if (outcome.isResolved) {
      _recordResolvedAlert(outcome.alert!);
      _showMessage('Alert ${outcome.alert!.statusLabel.toLowerCase()}.');
    } else {
      _showMessage(
        outcome.failure?.message ??
            'The alert state could not be confirmed. Refresh and try again.',
      );
    }
    if (mounted) setState(() => _resolvingAlertId = null);
  }

  Future<void> _openAlert(AlertInfo alert) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => AlertDetailScreen(
          alert: alert,
          snapshot: widget.snapshot,
          repository: _repository,
          onAlertResolved: _recordResolvedAlert,
        ),
      ),
    );
  }

  void _openMonitoring(MonitoringIncident incident) {
    setState(() => _focusedMonitoringId = incident.id);
    _showMonitoringDetails(incident);
  }

  Future<void> _showMonitoringDetails(MonitoringIncident incident) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.background,
      builder: (context) => _MonitoringIncidentDetails(incident: incident),
    );
  }

  void _recordResolvedAlert(AlertInfo alert) {
    if (alert.isActive) return;
    setState(() {
      _resolvedAlertOverlay[alert.id] = alert;
      _waterActive.items = _waterActive.items
          .where((item) => item.id != alert.id)
          .toList(growable: false);
      _waterActive.total = _waterActive.items.length;
      if (_waterHistory.loaded || _view == AlertView.history) {
        _waterHistory.items = _insertHistoryAlert(_waterHistory.items, alert);
        _waterHistory.total = _waterHistory.items.length;
      }
    });
    widget.onAlertResolved?.call(alert);
    unawaited(_loadWaterQuality(history: false));
    if (_waterHistory.loaded ||
        _stream == AlertStream.waterQuality && _view == AlertView.history) {
      unawaited(_loadWaterQuality(history: true));
    }
  }

  List<AlertInfo> _insertHistoryAlert(
    List<AlertInfo> existing,
    AlertInfo alert,
  ) {
    final result = <AlertInfo>[
      alert,
      ...existing.where((item) => item.id != alert.id),
    ];
    result.sort((left, right) {
      final leftAt = left.startedAt;
      final rightAt = right.startedAt;
      if (leftAt != null && rightAt != null) {
        final order = rightAt.compareTo(leftAt);
        if (order != 0) return order;
      }
      return (int.tryParse(right.id) ?? 0).compareTo(
        int.tryParse(left.id) ?? 0,
      );
    });
    return List.unmodifiable(result);
  }

  List<AlertInfo> _mergeHistoryAlerts(List<AlertInfo> loadedAlerts) {
    final merged = <String, AlertInfo>{
      for (final alert in loadedAlerts) alert.id: alert,
      ..._resolvedAlertOverlay,
    }.values.toList(growable: true);
    merged.sort((left, right) {
      final leftAt = left.startedAt;
      final rightAt = right.startedAt;
      if (leftAt != null && rightAt != null) {
        final order = rightAt.compareTo(leftAt);
        if (order != 0) return order;
      }
      return (int.tryParse(right.id) ?? 0).compareTo(
        int.tryParse(left.id) ?? 0,
      );
    });
    return List.unmodifiable(merged);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  static ApiFailure _safeFailure(Object error) => error is ApiFailure
      ? error
      : const ApiFailure(
          kind: ApiFailureKind.unknown,
          message: 'Alert data could not be loaded. Try again.',
          retryable: true,
        );
}

class _AlertCollection<T> {
  List<T> items = const [];
  bool loading = false;
  bool refreshing = false;
  bool loaded = false;
  ApiFailure? failure;
  DateTime? lastLoadedAt;
  int total = 0;
  int page = 0;
  int pageSize = 25;
  bool hasNext = false;
  bool loadingMore = false;
  ApiFailure? nextPageFailure;

  void reset() {
    items = const [];
    loading = false;
    refreshing = false;
    loaded = false;
    failure = null;
    lastLoadedAt = null;
    total = 0;
    page = 0;
    pageSize = 25;
    hasNext = false;
    loadingMore = false;
    nextPageFailure = null;
  }
}

class _MonitoringIncidentDetails extends StatelessWidget {
  const _MonitoringIncidentDetails({required this.incident});

  final MonitoringIncident incident;

  @override
  Widget build(BuildContext context) {
    final color = incident.isActive
        ? AppColors.offline
        : incident.resolutionReason ==
              MonitoringResolutionReason.reportingRecovered
        ? AppColors.tealDark
        : AppColors.muted;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(LucideIcons.radio, color: AppColors.offline),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    incident.tankName,
                    style: const TextStyle(
                      color: AppColors.text,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    border: Border.all(color: color.withValues(alpha: 0.4)),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    incident.lifecycleLabel,
                    style: TextStyle(
                      color: color,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Monitoring incident · reporting state, not water quality',
              style: TextStyle(
                color: AppColors.muted,
                fontSize: 11,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 15),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: AppColors.line),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  _MonitoringInfoRow(
                    label: 'Outage began',
                    value: incident.startedAt == null
                        ? incident.startedLabel
                        : formatLocalTimestamp(incident.startedAt!),
                    icon: LucideIcons.clock3,
                  ),
                  if (incident.detectedAt != null) ...[
                    const Divider(height: 1),
                    _MonitoringInfoRow(
                      label: 'Detected',
                      value: formatLocalTimestamp(incident.detectedAt!),
                      icon: LucideIcons.radar,
                    ),
                  ],
                  if (incident.lastReadingReceivedAt != null) ...[
                    const Divider(height: 1),
                    _MonitoringInfoRow(
                      label: 'Last report received',
                      value: formatLocalTimestamp(
                        incident.lastReadingReceivedAt!,
                      ),
                      icon: LucideIcons.activity,
                    ),
                  ] else if (incident.lastReportAgeSeconds != null) ...[
                    const Divider(height: 1),
                    _MonitoringInfoRow(
                      label: 'Last report',
                      value:
                          '${formatDurationSeconds(incident.lastReportAgeSeconds!)} ago',
                      icon: LucideIcons.activity,
                    ),
                  ],
                  if (incident.durationSeconds != null) ...[
                    const Divider(height: 1),
                    _MonitoringInfoRow(
                      label: 'Duration',
                      value: formatDurationSeconds(incident.durationSeconds!),
                      icon: LucideIcons.hourglass,
                    ),
                  ],
                  if (incident.resolvedAt != null) ...[
                    const Divider(height: 1),
                    _MonitoringInfoRow(
                      label: 'Resolved',
                      value: formatLocalTimestamp(incident.resolvedAt!),
                      icon: LucideIcons.circleCheck,
                    ),
                    const Divider(height: 1),
                    _MonitoringInfoRow(
                      label: 'Resolution',
                      value: incident.resolutionMessage,
                      icon: LucideIcons.info,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              incident.isActive
                  ? 'This is a backend monitoring outage record. Phone connectivity problems are shown separately.'
                  : incident.resolutionMessage,
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonitoringInfoRow extends StatelessWidget {
  const _MonitoringInfoRow({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: AppColors.muted),
        const SizedBox(width: 8),
        SizedBox(
          width: 112,
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 10.5,
              height: 1.3,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

class _WaterQualityList extends StatelessWidget {
  const _WaterQualityList({
    required this.alerts,
    required this.loading,
    required this.refreshing,
    required this.loaded,
    required this.failure,
    required this.showHistory,
    required this.onOpen,
    required this.onMarkHandled,
    required this.resolvingAlertId,
    required this.onRetry,
  });

  final List<AlertInfo> alerts;
  final bool loading;
  final bool refreshing;
  final bool loaded;
  final ApiFailure? failure;
  final bool showHistory;
  final ValueChanged<AlertInfo> onOpen;
  final ValueChanged<AlertInfo> onMarkHandled;
  final String? resolvingAlertId;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    if (loading && !loaded) {
      return const _LoadingNotice(label: 'Loading water-quality alerts');
    }
    if (failure != null && alerts.isEmpty) {
      return _SourceFailureNotice(message: failure!.message, onRetry: onRetry);
    }
    if (loaded && alerts.isEmpty) {
      return Column(
        children: [
          if (refreshing) const _InlineRefreshingNotice(),
          EmptyState(
            title: showHistory
                ? 'No alert history yet.'
                : 'No active water-quality alerts.',
            message: showHistory
                ? 'Resolved water-quality records will appear here.'
                : 'No current parameter conditions need acknowledgement.',
            icon: showHistory ? LucideIcons.history : LucideIcons.circleCheck,
          ),
          if (failure != null)
            _SourceFailureNotice(message: failure!.message, onRetry: onRetry),
        ],
      );
    }
    return Column(
      children: [
        if (refreshing) const _InlineRefreshingNotice(),
        if (failure != null)
          _SourceFailureNotice(message: failure!.message, onRetry: onRetry),
        for (var index = 0; index < alerts.length; index++) ...[
          if (showHistory)
            AlertHistoryRow(
              alert: alerts[index],
              onTap: () => onOpen(alerts[index]),
            )
          else
            AlertTile(
              alert: alerts[index],
              onTap: () => onOpen(alerts[index]),
              onMarkHandled: () => onMarkHandled(alerts[index]),
              resolving: resolvingAlertId == alerts[index].id,
              resolveDisabled: resolvingAlertId != null,
            ),
          if (index < alerts.length - 1) const SizedBox(height: 9),
        ],
      ],
    );
  }
}

class _MonitoringList extends StatelessWidget {
  const _MonitoringList({
    required this.incidents,
    required this.loading,
    required this.refreshing,
    required this.loaded,
    required this.failure,
    required this.showHistory,
    required this.onOpen,
    required this.hasNext,
    required this.loadingMore,
    required this.nextPageFailure,
    required this.onLoadMore,
    required this.onRetry,
    required this.onRetryNext,
    this.focusedId,
  });

  final List<MonitoringIncident> incidents;
  final bool loading;
  final bool refreshing;
  final bool loaded;
  final ApiFailure? failure;
  final bool showHistory;
  final String? focusedId;
  final ValueChanged<MonitoringIncident> onOpen;
  final bool hasNext;
  final bool loadingMore;
  final ApiFailure? nextPageFailure;
  final Future<void> Function() onLoadMore;
  final Future<void> Function() onRetry;
  final Future<void> Function() onRetryNext;

  @override
  Widget build(BuildContext context) {
    if (loading && !loaded) {
      return const _LoadingNotice(label: 'Loading monitoring incidents');
    }
    if (failure != null && incidents.isEmpty) {
      return _SourceFailureNotice(message: failure!.message, onRetry: onRetry);
    }
    if (loaded && incidents.isEmpty) {
      return Column(
        children: [
          if (refreshing) const _InlineRefreshingNotice(),
          EmptyState(
            title: showHistory
                ? 'No monitoring history yet.'
                : 'No monitoring outages.',
            message: showHistory
                ? 'Resolved monitoring interruptions will appear here.'
                : 'All monitored tanks are currently reporting.',
            icon: showHistory ? LucideIcons.history : LucideIcons.radio,
          ),
          if (failure != null)
            _SourceFailureNotice(message: failure!.message, onRetry: onRetry),
          if (hasNext || nextPageFailure != null || loadingMore)
            _MonitoringPagination(
              hasNext: hasNext,
              loadingMore: loadingMore,
              failure: nextPageFailure,
              onLoadMore: onLoadMore,
              onRetry: onRetryNext,
            ),
        ],
      );
    }
    return Column(
      children: [
        if (refreshing) const _InlineRefreshingNotice(),
        if (failure != null)
          _SourceFailureNotice(message: failure!.message, onRetry: onRetry),
        for (var index = 0; index < incidents.length; index++) ...[
          MonitoringIncidentTile(
            key: ValueKey('monitoring-incident-${incidents[index].id}'),
            incident: incidents[index],
            highlighted: focusedId == incidents[index].id,
            onTap: () => onOpen(incidents[index]),
          ),
          if (index < incidents.length - 1) const SizedBox(height: 9),
        ],
        if (hasNext || nextPageFailure != null || loadingMore)
          _MonitoringPagination(
            hasNext: hasNext,
            loadingMore: loadingMore,
            failure: nextPageFailure,
            onLoadMore: onLoadMore,
            onRetry: onRetryNext,
          ),
      ],
    );
  }
}

class _LoadingNotice extends StatelessWidget {
  const _LoadingNotice({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => _NoticeCard(
    key: ValueKey('alerts-loading-${label.toLowerCase().replaceAll(' ', '-')}'),
    child: Row(
      children: [
        const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.tealDark,
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

class _InlineRefreshingNotice extends StatelessWidget {
  const _InlineRefreshingNotice();

  @override
  Widget build(BuildContext context) => const _NoticeCard(
    child: Row(
      children: [
        SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 1.8,
            color: AppColors.tealDark,
          ),
        ),
        SizedBox(width: 9),
        Text(
          'Refreshing incident data',
          style: TextStyle(
            color: AppColors.muted,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    ),
  );
}

class _SourceFailureNotice extends StatelessWidget {
  const _SourceFailureNotice({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => _NoticeCard(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Icon(LucideIcons.cloudOff, color: AppColors.offline, size: 19),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 11,
              height: 1.3,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        TextButton(
          key: const ValueKey('alerts-source-retry'),
          onPressed: () => unawaited(onRetry()),
          child: const Text('Retry'),
        ),
      ],
    ),
  );
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.84),
      border: Border.all(color: AppColors.line),
      borderRadius: BorderRadius.circular(15),
    ),
    child: child,
  );
}

class _MonitoringPagination extends StatelessWidget {
  const _MonitoringPagination({
    required this.hasNext,
    required this.loadingMore,
    required this.failure,
    required this.onLoadMore,
    required this.onRetry,
  });

  final bool hasNext;
  final bool loadingMore;
  final ApiFailure? failure;
  final Future<void> Function() onLoadMore;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    if (loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 14),
        child: Center(
          child: SizedBox(
            width: 19,
            height: 19,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (failure != null) {
      return _SourceFailureNotice(message: failure!.message, onRetry: onRetry);
    }
    if (!hasNext) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.center,
      child: TextButton.icon(
        key: const ValueKey('monitoring-load-more'),
        onPressed: () => unawaited(onLoadMore()),
        icon: const Icon(LucideIcons.chevronsDown, size: 17),
        label: const Text('Load more'),
      ),
    );
  }
}

class _AlertStreamSelector extends StatelessWidget {
  const _AlertStreamSelector({
    required this.selected,
    required this.waterQualityCount,
    required this.monitoringCount,
    required this.onSelected,
  });

  final AlertStream selected;
  final int? waterQualityCount;
  final int? monitoringCount;
  final ValueChanged<AlertStream> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('alert-stream-selector'),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.68),
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Expanded(
            child: _AlertStreamOption(
              stream: AlertStream.waterQuality,
              label: 'Water quality',
              count: waterQualityCount,
              icon: LucideIcons.droplets,
              selected: selected == AlertStream.waterQuality,
              onTap: () => onSelected(AlertStream.waterQuality),
            ),
          ),
          Expanded(
            child: _AlertStreamOption(
              stream: AlertStream.monitoring,
              label: 'Monitoring',
              count: monitoringCount,
              icon: LucideIcons.radio,
              selected: selected == AlertStream.monitoring,
              onTap: () => onSelected(AlertStream.monitoring),
            ),
          ),
        ],
      ),
    );
  }
}

class _AlertStreamOption extends StatelessWidget {
  const _AlertStreamOption({
    required this.stream,
    required this.label,
    required this.count,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final AlertStream stream;
  final String label;
  final int? count;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label:
          '$label, ${count?.toString() ?? 'count unavailable'} active ${stream == AlertStream.monitoring ? 'incidents' : 'alerts'}',
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          key: ValueKey('alert-stream-${stream.name}'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 11),
            decoration: BoxDecoration(
              color: selected ? AppColors.mint : Colors.transparent,
              border: Border.all(
                color: selected
                    ? AppColors.teal.withValues(alpha: 0.28)
                    : Colors.transparent,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final stacked =
                    constraints.maxWidth < 155 ||
                    MediaQuery.textScalerOf(context).scale(1) > 1.4;
                final iconWidget = Icon(
                  icon,
                  size: 19,
                  color: selected ? AppColors.tealDark : AppColors.muted,
                );
                final labelWidget = Flexible(
                  child: Text(
                    label,
                    maxLines: stacked ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: stacked ? TextAlign.center : TextAlign.start,
                    style: TextStyle(
                      color: selected ? AppColors.text : AppColors.muted,
                      fontSize: 12,
                      height: 1.15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
                final countWidget = _CountBadge(
                  count: count,
                  selected: selected,
                );
                if (stacked) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          iconWidget,
                          const SizedBox(width: 6),
                          countWidget,
                        ],
                      ),
                      const SizedBox(height: 4),
                      labelWidget,
                    ],
                  );
                }
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    iconWidget,
                    const SizedBox(width: 7),
                    labelWidget,
                    const SizedBox(width: 7),
                    countWidget,
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count, required this.selected});

  final int? count;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 27, minHeight: 27),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected
            ? AppColors.teal.withValues(alpha: 0.13)
            : AppColors.line.withValues(alpha: 0.55),
        shape: BoxShape.circle,
      ),
      child: Text(
        count?.toString() ?? '–',
        key: ValueKey(
          'alert-count-${count ?? 'unknown'}-${selected ? 'selected' : 'quiet'}',
        ),
        style: TextStyle(
          color: selected ? AppColors.tealDark : AppColors.muted,
          fontSize: 11,
          height: 1,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _AlertStateTabs extends StatelessWidget {
  const _AlertStateTabs({required this.selected, required this.onSelected});

  final AlertView selected;
  final ValueChanged<AlertView> onSelected;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Alert state filter',
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 270),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SizedBox(
                width: constraints.maxWidth,
                child: Container(
                  key: const ValueKey('alert-state-tabs'),
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.55),
                    border: Border.all(color: AppColors.line),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _AlertStateOption(
                          view: AlertView.active,
                          selected: selected == AlertView.active,
                          onTap: () => onSelected(AlertView.active),
                        ),
                      ),
                      Expanded(
                        child: _AlertStateOption(
                          view: AlertView.history,
                          selected: selected == AlertView.history,
                          onTap: () => onSelected(AlertView.history),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _AlertStateOption extends StatelessWidget {
  const _AlertStateOption({
    required this.view,
    required this.selected,
    required this.onTap,
  });

  final AlertView view;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = view == AlertView.active ? 'Active' : 'History';
    return Semantics(
      button: true,
      selected: selected,
      label: '$label alerts',
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          key: ValueKey('alert-state-${view.name}'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(11),
          child: AnimatedContainer(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 140),
            constraints: const BoxConstraints(minHeight: 38),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? AppColors.mint.withValues(alpha: 0.82) : null,
              borderRadius: BorderRadius.circular(11),
              border: selected
                  ? Border.all(color: AppColors.teal.withValues(alpha: 0.16))
                  : null,
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? AppColors.text : AppColors.muted,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AlertSummary extends StatelessWidget {
  const _AlertSummary({
    required this.criticalCount,
    required this.warningCount,
    required this.monitoringCount,
  });

  final int? criticalCount;
  final int? warningCount;
  final int? monitoringCount;

  @override
  Widget build(BuildContext context) {
    final summary =
        '${criticalCount?.toString() ?? 'Unknown'} Critical, ${warningCount?.toString() ?? 'Unknown'} Warning, ${monitoringCount?.toString() ?? 'Unknown'} Monitoring';
    return Semantics(
      container: true,
      label: summary,
      child: Container(
        key: const ValueKey('alert-summary-strip'),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: AppColors.line),
          borderRadius: BorderRadius.circular(17),
        ),
        child: Row(
          children: [
            Expanded(
              child: _SummaryItem(
                count: criticalCount,
                label: 'Critical',
                color: AppColors.critical,
              ),
            ),
            const _MetricDivider(),
            Expanded(
              child: _SummaryItem(
                count: warningCount,
                label: 'Warning',
                color: AppColors.warning,
              ),
            ),
            const _MetricDivider(),
            Expanded(
              child: _SummaryItem(
                count: monitoringCount,
                label: 'Monitoring',
                color: AppColors.offline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  const _SummaryItem({
    required this.count,
    required this.label,
    required this.color,
  });

  final int? count;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        children: [
          Text(
            count?.toString() ?? '–',
            key: ValueKey('alert-summary-count-${label.toLowerCase()}'),
            style: TextStyle(
              color: color,
              fontSize: 22,
              height: 1.05,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 11,
              height: 1.1,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricDivider extends StatelessWidget {
  const _MetricDivider();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: VerticalDivider(
        width: 1,
        thickness: 1,
        color: AppColors.line.withValues(alpha: 0.95),
      ),
    );
  }
}

T? _firstOrNull<T>(Iterable<T> values) {
  final iterator = values.iterator;
  return iterator.moveNext() ? iterator.current : null;
}

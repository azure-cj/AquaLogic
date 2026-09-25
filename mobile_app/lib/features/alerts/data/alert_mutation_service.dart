import 'package:aqualogic/features/alerts/data/mock_alert_repository.dart';
import 'package:aqualogic/features/alerts/models/alert_info.dart';
import 'package:aqualogic/features/sensors/models/sensor_snapshot.dart';
import 'package:aqualogic/shared/network/api_failure.dart';

class AlertMutationOutcome {
  const AlertMutationOutcome({
    this.alert,
    this.failure,
    this.reconciled = false,
  });

  final AlertInfo? alert;
  final ApiFailure? failure;
  final bool reconciled;

  bool get isResolved => alert != null && !alert!.isActive;
}

/// Resolves an alert once and reconciles potentially ambiguous failures with
/// the read API instead of blindly replaying an operational mutation.
Future<AlertMutationOutcome> markAlertHandled({
  required AlertRepository repository,
  required SensorSnapshot snapshot,
  required AlertInfo alert,
}) async {
  try {
    final result = await repository.resolveAlert(alert.id);
    if (!result.isActive) return AlertMutationOutcome(alert: result);
    return AlertMutationOutcome(
      failure: const ApiFailure(
        kind: ApiFailureKind.unknown,
        message: 'AquaLogic did not confirm that the alert was handled.',
        retryable: true,
      ),
    );
  } on ApiFailure catch (failure) {
    if (!_mayHaveReachedBackend(failure)) {
      return AlertMutationOutcome(failure: failure);
    }
    try {
      final current = await repository.findWaterQualityAlert(
        snapshot: snapshot,
        alertId: alert.id,
      );
      if (current != null) {
        return AlertMutationOutcome(
          alert: current,
          failure: current.isActive ? failure : null,
          reconciled: true,
        );
      }
    } catch (_) {
      // Keep the original safe mutation error; a failed reconciliation does
      // not change the alert's confirmed state.
    }
    return AlertMutationOutcome(failure: failure, reconciled: true);
  } catch (_) {
    return const AlertMutationOutcome(
      failure: ApiFailure(
        kind: ApiFailureKind.unknown,
        message:
            'The alert state could not be confirmed. Refresh and try again.',
        retryable: true,
      ),
    );
  }
}

bool _mayHaveReachedBackend(ApiFailure failure) =>
    failure.kind == ApiFailureKind.timeout ||
    failure.kind == ApiFailureKind.networkUnavailable ||
    failure.kind == ApiFailureKind.server;

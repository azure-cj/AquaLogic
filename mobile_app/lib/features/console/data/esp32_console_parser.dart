import 'dart:convert';
import '../models/console_state.dart';

class Esp32ConsoleParser {
  static Map<String, dynamic> object(String body) {
    final value = jsonDecode(body);
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Expected a JSON object');
    }
    return value;
  }

  static double? number(Object? value) =>
      value is num && value.isFinite ? value.toDouble() : null;
  static bool? boolean(Object? value) => value is bool ? value : null;
  static int? counter(Object? value) =>
      value is int && value >= 0 ? value : null;
  static ConsolePumpState pumpDetails(Map<String, dynamic>? data) =>
      ConsolePumpState(
        active: boolean(data?['active']),
        doseCount: counter(data?['dose_count']),
        volumeMl: number(data?['volume_ml']),
        remainingMl: number(data?['remaining_ml']),
        capacityMl: number(data?['capacity_ml']),
        volumeKnown: boolean(data?['volume_known']),
        refillRequired: boolean(data?['refill_required']),
        clockSynced: boolean(data?['clock_synced']),
        nextEligibleAt: data?['next_eligible_at'] is String
            ? data!['next_eligible_at'] as String
            : null,
      );
  static String? status(Object? value) =>
      value is String ? value.toUpperCase() : null;
  static ConsoleWaterQuality? quality(Object? value) => switch (value) {
    'GOOD' => ConsoleWaterQuality.normal,
    'MONITOR' => ConsoleWaterQuality.attention,
    'CRITICAL' => ConsoleWaterQuality.critical,
    _ => null,
  };
  static String pump(Map<String, dynamic>? data) => switch (data?['active']) {
    true => 'RUNNING',
    false => 'IDLE',
    _ => 'UNKNOWN',
  };
  static ConsoleEquipmentState equipment(
    Map<String, Map<String, dynamic>?> responses,
  ) {
    final light = boolean(responses['/led/status']?['led_on']);
    final uv = boolean(responses['/uv/status']?['led_on']);
    final feeding = boolean(responses['/feeder/status']?['feeding']);
    return ConsoleEquipmentState(
      lightOn: light == true,
      uvOn: uv == true,
      feederRunning: feeding == true,
      lightConfirmed: light != null,
      uvConfirmed: uv != null,
      feederConfirmed: feeding != null,
      pumpAStatus: pump(responses['/syringeA/status']),
      pumpBStatus: pump(responses['/syringeB/status']),
      pumpA: pumpDetails(responses['/syringeA/status']),
      pumpB: pumpDetails(responses['/syringeB/status']),
      feedCount: counter(responses['/feeder/status']?['feed_count']),
    );
  }
}

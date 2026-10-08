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
        nextEligibleAt: text(data?['next_eligible_at']),
        lastDispensed: text(data?['last_dispensed']),
        nextDoseAt: text(data?['next_dose_at']),
        scheduleEvent: text(data?['schedule_event']),
      );

  /// Firmware time strings; blank values count as not reported.
  static String? text(Object? value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;

  /// Exactly three valid slots, or nothing; partial schedules are not shown.
  static List<ConsoleScheduleSlot> schedule(Object? value) {
    if (value is! List || value.length != 3) return const [];
    final slots = <ConsoleScheduleSlot>[];
    for (final slot in value) {
      if (slot is! Map) return const [];
      final hour = slot['hour'], minute = slot['minute'];
      final enabled = slot['enabled'];
      if (hour is! int || hour < 0 || hour > 23) return const [];
      if (minute is! int || minute < 0 || minute > 59) return const [];
      if (enabled is! bool) return const [];
      slots.add(ConsoleScheduleSlot(hour, minute, enabled: enabled));
    }
    return slots;
  }

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
    final feeder = responses['/feeder/status'];
    final feeding = boolean(feeder?['feeding']);
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
      feedCount: counter(feeder?['feed_count']),
      lastFed: text(feeder?['last_fed']),
      feederAngle: counter(feeder?['open_angle']),
      feederDurationMs: counter(feeder?['duration_ms']),
      feederSchedule: schedule(feeder?['schedule']),
    );
  }
}

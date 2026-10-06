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
    );
  }
}

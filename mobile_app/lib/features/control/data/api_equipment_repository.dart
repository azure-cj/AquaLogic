import 'dart:async';

import 'package:aqualogic/features/control/data/mock_equipment_repository.dart';
import 'package:aqualogic/features/control/models/equipment_models.dart';
import 'package:aqualogic/shared/formatters/local_timestamps.dart';
import 'package:aqualogic/shared/models/aqualogic_status.dart';
import 'package:aqualogic/shared/network/api_client.dart';
import 'package:aqualogic/shared/network/api_failure.dart';

/// M5 read-only equipment integration. This repository deliberately exposes no
/// actuator-command method and only issues GET requests.
class ApiEquipmentRepository implements EquipmentRepository {
  ApiEquipmentRepository({required this.apiClient});

  static const devicesPath = '/devices';
  static const historyPageSize = 10;

  final ApiClient apiClient;

  @override
  bool get isLiveData => true;

  @override
  bool get supportsCommandSimulation => false;

  @override
  Future<List<RegisteredEquipmentDevice>> listDevices({
    required String tankId,
  }) async {
    final id = int.tryParse(tankId);
    if (id == null || id <= 0) throw ApiFailure.fromStatus(404);
    try {
      final response = await apiClient.get(devicesPath, authenticated: true);
      if (response.body is! List) {
        throw const FormatException('Expected device inventory list.');
      }
      final devices = (response.body as List)
          .map(RegisteredDeviceDto.fromJson)
          .where((device) => device.tankId == id)
          .map((device) => device.toDomain())
          .toList(growable: false);
      return devices;
    } on ApiFailure {
      rethrow;
    } on FormatException {
      throw _unreadable('registered equipment');
    }
  }

  @override
  Future<EquipmentOverview> load({
    required String tankId,
    required RegisteredEquipmentDevice device,
    int historyPage = 1,
  }) async {
    final tank = int.tryParse(tankId);
    if (tank == null || tank <= 0 || tank != device.tankId || historyPage < 1) {
      throw ApiFailure.fromStatus(404);
    }

    final statusRequest = _captureStatus(tank, device);
    final historyRequest = _captureHistory(tank, device, historyPage);
    final results = await Future.wait<_SourceResult<Object>>([
      statusRequest,
      historyRequest,
    ]);
    final status = results[0] as _SourceResult<ActuatorStatusDto>;
    final history = results[1] as _SourceResult<ActuatorHistoryPageDto>;

    final historyItems = history.value?.items ?? const <ActuatorCommandDto>[];
    final latestActions = <String, ActuatorCommandDto>{};
    for (final command in historyItems) {
      latestActions.putIfAbsent(command.actuator, () => command);
    }

    return EquipmentOverview(
      devices: status.value == null
          ? const []
          : status.value!.toEquipmentDevices(
              registeredDevice: device,
              latestActions: latestActions,
            ),
      commandHistory: historyItems
          .map((command) => command.toDomain())
          .toList(growable: false),
      historyHasNextPage: history.value?.hasNextPage ?? false,
      statusFailure: status.failure,
      historyFailure: history.failure,
    );
  }

  Future<_SourceResult<ActuatorStatusDto>> _captureStatus(
    int tankId,
    RegisteredEquipmentDevice device,
  ) async {
    try {
      final path =
          '/tanks/$tankId/actuators/status'
          '?device_id=${Uri.encodeQueryComponent(device.id)}';
      final response = await apiClient.get(path, authenticated: true);
      final status = ActuatorStatusDto.fromJson(response.body);
      if (status.tankId != tankId || status.deviceId != device.id) {
        throw const FormatException('Equipment status identity mismatch.');
      }
      return _SourceResult(value: status);
    } catch (error) {
      return _SourceResult(failure: _normalizeFailure(error, 'status'));
    }
  }

  Future<_SourceResult<ActuatorHistoryPageDto>> _captureHistory(
    int tankId,
    RegisteredEquipmentDevice device,
    int page,
  ) async {
    try {
      final path =
          '/tanks/$tankId/actuators/history'
          '?device_id=${Uri.encodeQueryComponent(device.id)}'
          '&page=$page&page_size=$historyPageSize';
      final response = await apiClient.get(path, authenticated: true);
      final history = ActuatorHistoryPageDto.fromJson(response.body);
      if (history.page != page) {
        throw const FormatException('Equipment history page mismatch.');
      }
      return _SourceResult(value: history);
    } catch (error) {
      return _SourceResult(failure: _normalizeFailure(error, 'history'));
    }
  }

  ApiFailure _normalizeFailure(Object error, String source) {
    if (error is ApiFailure && error.statusCode == 409) {
      return const ApiFailure(
        kind: ApiFailureKind.conflict,
        statusCode: 409,
        message:
            'The selected equipment is ambiguous. Refresh the device list and select a registered device.',
      );
    }
    if (error is ApiFailure) return error;
    return _unreadable('equipment $source');
  }

  ApiFailure _unreadable(String source) => ApiFailure(
    kind: ApiFailureKind.unknown,
    message: 'AquaLogic returned unreadable $source information.',
  );
}

class RegisteredDeviceDto {
  const RegisteredDeviceDto({
    required this.id,
    required this.tankId,
    required this.tankName,
    required this.status,
    required this.lastSeenAt,
  });

  final String id;
  final int tankId;
  final String tankName;
  final String status;
  final DateTime? lastSeenAt;

  factory RegisteredDeviceDto.fromJson(Object? value) {
    final json = _jsonMap(value, 'registered device');
    final status = _requiredString(json, 'status');
    if (status != 'online' && status != 'offline' && status != 'disabled') {
      throw const FormatException('Unknown registered-device status.');
    }
    return RegisteredDeviceDto(
      id: _requiredString(json, 'device_id'),
      tankId: _requiredInt(json, 'tank_id'),
      tankName: _requiredString(json, 'tank_name'),
      status: status,
      lastSeenAt: _optionalDateTime(json, 'last_seen_at'),
    );
  }

  RegisteredEquipmentDevice toDomain() => RegisteredEquipmentDevice(
    id: id,
    tankId: tankId,
    tankName: tankName,
    connection: switch (status) {
      'online' => DeviceConnectionStatus.online,
      'offline' => DeviceConnectionStatus.offline,
      'disabled' => DeviceConnectionStatus.disabled,
      _ => DeviceConnectionStatus.unknown,
    },
    lastSeenAt: lastSeenAt,
  );
}

class ActuatorStatusDto {
  const ActuatorStatusDto({
    required this.tankId,
    required this.deviceId,
    required this.deviceFreshness,
    required this.actuators,
  });

  final int tankId;
  final String deviceId;
  final String deviceFreshness;
  final List<ActuatorStateDto> actuators;

  factory ActuatorStatusDto.fromJson(Object? value) {
    final json = _jsonMap(value, 'actuator status');
    final freshness = _requiredString(json, 'device_freshness');
    if (freshness != 'online' &&
        freshness != 'offline' &&
        freshness != 'unknown') {
      throw const FormatException('Unknown actuator device freshness.');
    }
    final rows = json['actuators'];
    if (rows is! List) {
      throw const FormatException('Expected actuator state list.');
    }
    final parsed = rows.map(ActuatorStateDto.fromJson).toList(growable: false);
    final names = parsed.map((item) => item.actuator).toSet();
    if (names.length != parsed.length) {
      throw const FormatException('Duplicate actuator state.');
    }
    return ActuatorStatusDto(
      tankId: _requiredInt(json, 'tank_id'),
      deviceId: _requiredString(json, 'device_id'),
      deviceFreshness: freshness,
      actuators: parsed,
    );
  }

  List<EquipmentDevice> toEquipmentDevices({
    required RegisteredEquipmentDevice registeredDevice,
    required Map<String, ActuatorCommandDto> latestActions,
  }) {
    final connection =
        registeredDevice.connection == DeviceConnectionStatus.disabled
        ? DeviceConnectionStatus.disabled
        : switch (deviceFreshness) {
            'online' => DeviceConnectionStatus.online,
            'offline' => DeviceConnectionStatus.offline,
            'unknown' => DeviceConnectionStatus.unknown,
            _ => DeviceConnectionStatus.unknown,
          };
    final byActuator = {for (final state in actuators) state.actuator: state};
    return [
      for (final actuator in const ['uv', 'led', 'feeder', 'pump_a', 'pump_b'])
        _mapActuator(
          actuator,
          byActuator[actuator],
          connection,
          latestActions[actuator],
          registeredDevice.id,
        ),
      for (final actuator in actuators)
        if (!const {
          'uv',
          'led',
          'feeder',
          'pump_a',
          'pump_b',
        }.contains(actuator.actuator))
          _unknownActuator(actuator.actuator, connection, registeredDevice.id),
    ];
  }
}

class ActuatorStateDto {
  const ActuatorStateDto({
    required this.actuator,
    required this.state,
    required this.refreshedAt,
  });

  final String actuator;
  final Map<String, Object?>? state;
  final DateTime? refreshedAt;

  factory ActuatorStateDto.fromJson(Object? value) {
    final json = _jsonMap(value, 'actuator state');
    final rawState = json['state'];
    return ActuatorStateDto(
      actuator: _requiredString(json, 'actuator'),
      state: rawState == null ? null : _jsonMap(rawState, 'actuator value'),
      refreshedAt: _optionalDateTime(json, 'refreshed_at'),
    );
  }
}

class ActuatorHistoryPageDto {
  const ActuatorHistoryPageDto({
    required this.items,
    required this.page,
    required this.hasNextPage,
  });

  final List<ActuatorCommandDto> items;
  final int page;
  final bool hasNextPage;

  factory ActuatorHistoryPageDto.fromJson(Object? value) {
    final json = _jsonMap(value, 'actuator history');
    final rows = json['items'];
    if (rows is! List) {
      throw const FormatException('Expected actuator history list.');
    }
    return ActuatorHistoryPageDto(
      items: rows.map(ActuatorCommandDto.fromJson).toList(growable: false),
      page: _requiredInt(json, 'page'),
      hasNextPage: _requiredBool(json, 'has_next'),
    );
  }
}

class ActuatorCommandDto {
  const ActuatorCommandDto({
    required this.id,
    required this.actuator,
    required this.action,
    required this.status,
    required this.requestedAt,
  });

  final String id;
  final String actuator;
  final String action;
  final CommandStatus status;
  final DateTime requestedAt;

  factory ActuatorCommandDto.fromJson(Object? value) {
    final json = _jsonMap(value, 'actuator command');
    final rawStatus = _requiredString(json, 'status');
    final status = switch (rawStatus) {
      'queued' => CommandStatus.queued,
      'executing' => CommandStatus.executing,
      'succeeded' => CommandStatus.succeeded,
      'failed' => CommandStatus.failed,
      'expired' => CommandStatus.expired,
      'outcome_unknown' => CommandStatus.outcomeUnknown,
      _ => throw const FormatException('Unknown actuator command status.'),
    };
    return ActuatorCommandDto(
      id: _requiredString(json, 'command_id'),
      actuator: _requiredString(json, 'actuator'),
      action: _requiredString(json, 'action'),
      status: status,
      requestedAt: _requiredDateTime(json, 'requested_at'),
    );
  }

  CommandRecord toDomain() {
    final equipment = _equipmentName(actuator);
    return CommandRecord(
      id: id,
      equipmentId: actuator,
      equipmentName: equipment,
      actionLabel: _actionLabel(action),
      status: status,
      timeLabel: formatLocalTimestamp(requestedAt),
      detail: status == CommandStatus.outcomeUnknown
          ? 'The backend could not confirm the command outcome.'
          : null,
    );
  }
}

EquipmentDevice _mapActuator(
  String actuator,
  ActuatorStateDto? dto,
  DeviceConnectionStatus connection,
  ActuatorCommandDto? latestAction,
  String deviceId,
) {
  final identity = _equipmentIdentity(actuator);
  final state = dto?.state;
  if (state == null) {
    return EquipmentDevice(
      id: '$deviceId:$actuator',
      name: identity.name,
      subtitle: identity.subtitle,
      kind: identity.kind,
      powerState: EquipmentPowerState.unknown,
      reportedStateLabel: 'No state reported',
      connection: connection,
      scheduleLabel: 'No current state or schedule has been reported.',
      lastActionLabel: _lastAction(latestAction),
      stateRefreshedAt: dto?.refreshedAt,
    );
  }

  late final EquipmentPowerState power;
  late final String reportedState;
  late final String detail;
  switch (actuator) {
    case 'uv':
    case 'led':
      final on = _requiredBool(state, 'on');
      final remaining = _requiredInt(state, 'remaining_ms');
      final scheduleEnabled = _requiredBool(state, 'schedule_enabled');
      final onTime = _requiredString(state, 'on_time');
      final offTime = _requiredString(state, 'off_time');
      power = on ? EquipmentPowerState.on : EquipmentPowerState.off;
      reportedState = on ? 'On' : 'Off';
      detail = scheduleEnabled
          ? 'Device schedule $onTime–$offTime'
          : remaining > 0
          ? 'Timer remaining ${_duration(remaining)}'
          : 'No timer or schedule reported';
    case 'feeder':
      final feeding = _requiredBool(state, 'feeding');
      final lastFed = _requiredString(state, 'last_fed');
      final schedule = state['schedule'];
      if (schedule is! List) {
        throw const FormatException('Expected feeder schedule list.');
      }
      final times = <String>[];
      for (final rawSlot in schedule) {
        final slot = _jsonMap(rawSlot, 'feeder schedule slot');
        if (_requiredBool(slot, 'enabled')) {
          times.add(_requiredString(slot, 'time'));
        }
      }
      power = feeding ? EquipmentPowerState.ready : EquipmentPowerState.idle;
      reportedState = feeding ? 'Feeding' : 'Idle';
      detail = [
        if (times.isEmpty) 'No scheduled feed times',
        if (times.isNotEmpty) 'Device schedule ${times.join(', ')}',
        'Last feed reported: $lastFed',
      ].join(' · ');
    case 'pump_a':
    case 'pump_b':
      final active = _requiredBool(state, 'active');
      final volume = _requiredDouble(state, 'volume_ml');
      final lastDispensed = _requiredString(state, 'last_dispensed');
      power = active ? EquipmentPowerState.ready : EquipmentPowerState.idle;
      reportedState = active ? 'Active' : 'Idle';
      detail = 'Last dispense reported: $lastDispensed · ${_number(volume)} ml';
    default:
      return _unknownActuator(actuator, connection, deviceId);
  }

  return EquipmentDevice(
    id: '$deviceId:$actuator',
    name: identity.name,
    subtitle: identity.subtitle,
    kind: identity.kind,
    powerState: power,
    reportedStateLabel: reportedState,
    connection: connection,
    scheduleLabel: detail,
    lastActionLabel: _lastAction(latestAction),
    stateRefreshedAt: dto?.refreshedAt,
  );
}

EquipmentDevice _unknownActuator(
  String actuator,
  DeviceConnectionStatus connection,
  String deviceId,
) => EquipmentDevice(
  id: '$deviceId:$actuator',
  name: 'Unrecognized equipment',
  subtitle: 'AquaLogic returned an unsupported equipment type.',
  kind: EquipmentKind.unknown,
  powerState: EquipmentPowerState.unknown,
  reportedStateLabel: 'State unavailable',
  connection: connection,
  scheduleLabel: 'This app does not display this equipment type.',
  lastActionLabel: 'History unavailable for this equipment type',
);

({EquipmentKind kind, String name, String subtitle}) _equipmentIdentity(
  String actuator,
) => switch (actuator) {
  'uv' => (
    kind: EquipmentKind.uv,
    name: 'UV Sterilizer',
    subtitle: 'Device-reported UV state',
  ),
  'led' => (
    kind: EquipmentKind.led,
    name: 'LED Lighting',
    subtitle: 'Device-reported light state',
  ),
  'feeder' => (
    kind: EquipmentKind.feeder,
    name: 'Automatic Feeder',
    subtitle: 'Device-reported feeder state',
  ),
  'pump_a' => (
    kind: EquipmentKind.pumpA,
    name: 'Pump A',
    subtitle: 'Device-reported pump state',
  ),
  'pump_b' => (
    kind: EquipmentKind.pumpB,
    name: 'Pump B',
    subtitle: 'Device-reported pump state',
  ),
  _ => (
    kind: EquipmentKind.unknown,
    name: 'Unrecognized equipment',
    subtitle: 'Unsupported equipment type',
  ),
};

String _equipmentName(String actuator) => _equipmentIdentity(actuator).name;

String _actionLabel(String action) => switch (action) {
  'on' => 'Turn on',
  'off' => 'Turn off',
  'timer' => 'Set timer',
  'schedule' => 'Update schedule',
  'feed_now' => 'Feed now',
  'config' => 'Update feeder settings',
  'dispense' => 'Dispense',
  'stop' => 'Stop pump',
  'retract' => 'Retract pump',
  _ => 'Actuator action',
};

String _lastAction(ActuatorCommandDto? command) => command == null
    ? 'No command in recent history'
    : '${_actionLabel(command.action)} · ${command.status.label}';

String _duration(int milliseconds) {
  if (milliseconds < 60000) return '< 1 min';
  final minutes = milliseconds ~/ 60000;
  final hours = minutes ~/ 60;
  final remaining = minutes % 60;
  if (hours == 0) return '$minutes min';
  return remaining == 0 ? '${hours}h' : '${hours}h ${remaining}m';
}

String _number(double value) =>
    value == value.truncateToDouble() ? value.toInt().toString() : '$value';

class _SourceResult<T> {
  const _SourceResult({this.value, this.failure});

  final T? value;
  final ApiFailure? failure;
}

Map<String, Object?> _jsonMap(Object? value, String label) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw FormatException('Expected a JSON object for $label.');
      }
      result[entry.key as String] = entry.value;
    }
    return result;
  }
  throw FormatException('Expected a JSON object for $label.');
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String) return value;
  throw FormatException('Expected string field $key.');
}

int _requiredInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is int) return value;
  throw FormatException('Expected integer field $key.');
}

bool _requiredBool(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is bool) return value;
  throw FormatException('Expected boolean field $key.');
}

double _requiredDouble(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is num && value.isFinite) return value.toDouble();
  throw FormatException('Expected numeric field $key.');
}

DateTime? _optionalDateTime(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) return parsed.toUtc();
  }
  throw FormatException('Expected nullable timestamp field $key.');
}

DateTime _requiredDateTime(Map<String, Object?> json, String key) {
  final value = _optionalDateTime(json, key);
  if (value != null) return value;
  throw FormatException('Expected timestamp field $key.');
}

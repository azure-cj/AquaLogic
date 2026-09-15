import 'package:aqualogic/shared/models/aqualogic_status.dart';

enum EquipmentKind { uv, led, feeder, pumpA, pumpB }

enum EquipmentPowerState { on, off, idle, ready, unknown }

class EquipmentDevice {
  const EquipmentDevice({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.kind,
    required this.powerState,
    required this.connection,
    required this.scheduleLabel,
    required this.lastActionLabel,
  });

  final String id;
  final String name;
  final String subtitle;
  final EquipmentKind kind;
  final EquipmentPowerState powerState;
  final DeviceConnectionStatus connection;
  final String scheduleLabel;
  final String lastActionLabel;

  bool get isPump => kind == EquipmentKind.pumpA || kind == EquipmentKind.pumpB;

  String get stateLabel => switch (powerState) {
    EquipmentPowerState.on => 'On',
    EquipmentPowerState.off => 'Off',
    EquipmentPowerState.idle => 'Idle',
    EquipmentPowerState.ready => 'Ready',
    EquipmentPowerState.unknown => 'State unknown',
  };

  EquipmentDevice copyWith({
    EquipmentPowerState? powerState,
    DeviceConnectionStatus? connection,
    String? scheduleLabel,
    String? lastActionLabel,
  }) {
    return EquipmentDevice(
      id: id,
      name: name,
      subtitle: subtitle,
      kind: kind,
      powerState: powerState ?? this.powerState,
      connection: connection ?? this.connection,
      scheduleLabel: scheduleLabel ?? this.scheduleLabel,
      lastActionLabel: lastActionLabel ?? this.lastActionLabel,
    );
  }
}

class CommandRecord {
  const CommandRecord({
    required this.id,
    required this.equipmentId,
    required this.equipmentName,
    required this.actionLabel,
    required this.status,
    required this.timeLabel,
    this.detail,
  });

  final String id;
  final String equipmentId;
  final String equipmentName;
  final String actionLabel;
  final CommandStatus status;
  final String timeLabel;
  final String? detail;

  CommandRecord copyWith({CommandStatus? status, String? detail}) {
    return CommandRecord(
      id: id,
      equipmentId: equipmentId,
      equipmentName: equipmentName,
      actionLabel: actionLabel,
      status: status ?? this.status,
      timeLabel: timeLabel,
      detail: detail ?? this.detail,
    );
  }
}

class EquipmentOverview {
  const EquipmentOverview({
    required this.devices,
    required this.commandHistory,
  });

  final List<EquipmentDevice> devices;
  final List<CommandRecord> commandHistory;
}

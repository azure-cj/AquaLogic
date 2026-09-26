import 'package:aqualogic/shared/models/aqualogic_status.dart';
import 'package:aqualogic/shared/network/api_failure.dart';

enum EquipmentKind { uv, led, feeder, pumpA, pumpB, unknown }

enum EquipmentPowerState { on, off, idle, ready, unknown }

class RegisteredEquipmentDevice {
  const RegisteredEquipmentDevice({
    required this.id,
    required this.tankId,
    required this.tankName,
    required this.connection,
    required this.lastSeenAt,
  });

  final String id;
  final int tankId;
  final String tankName;
  final DeviceConnectionStatus connection;
  final DateTime? lastSeenAt;

  String get selectionLabel => '$id · ${connection.label}';
}

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
    this.reportedStateLabel,
    this.stateRefreshedAt,
  });

  final String id;
  final String name;
  final String subtitle;
  final EquipmentKind kind;
  final EquipmentPowerState powerState;
  final DeviceConnectionStatus connection;
  final String scheduleLabel;
  final String lastActionLabel;
  final String? reportedStateLabel;
  final DateTime? stateRefreshedAt;

  bool get isPump => kind == EquipmentKind.pumpA || kind == EquipmentKind.pumpB;

  String get stateLabel =>
      reportedStateLabel ??
      switch (powerState) {
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
      reportedStateLabel: reportedStateLabel,
      stateRefreshedAt: stateRefreshedAt,
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
    this.historyHasNextPage = false,
    this.statusFailure,
    this.historyFailure,
  });

  final List<EquipmentDevice> devices;
  final List<CommandRecord> commandHistory;
  final bool historyHasNextPage;
  final ApiFailure? statusFailure;
  final ApiFailure? historyFailure;
}

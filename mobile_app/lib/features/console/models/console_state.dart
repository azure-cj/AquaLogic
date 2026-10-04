import 'console_command.dart';

enum ConsoleWaterQuality {
  normal,
  attention,
  critical;

  String get label => name.toUpperCase();
}

class ConsoleEquipmentState {
  const ConsoleEquipmentState({
    this.lightOn = true,
    this.uvOn = true,
    this.feederRunning = false,
    this.lightConfirmed = true,
    this.uvConfirmed = true,
    this.feederConfirmed = true,
  });
  final bool lightOn;
  final bool uvOn;
  final bool feederRunning;
  final bool lightConfirmed;
  final bool uvConfirmed;
  final bool feederConfirmed;
  // Pumps deliberately have no writable state or command surface in Phase 1.
  String get pumpAStatus => 'IDLE';
  String get pumpBStatus => 'IDLE';

  ConsoleEquipmentState copyWith({
    bool? lightOn,
    bool? uvOn,
    bool? feederRunning,
    bool? lightConfirmed,
    bool? uvConfirmed,
    bool? feederConfirmed,
  }) => ConsoleEquipmentState(
    lightOn: lightOn ?? this.lightOn,
    uvOn: uvOn ?? this.uvOn,
    feederRunning: feederRunning ?? this.feederRunning,
    lightConfirmed: lightConfirmed ?? this.lightConfirmed,
    uvConfirmed: uvConfirmed ?? this.uvConfirmed,
    feederConfirmed: feederConfirmed ?? this.feederConfirmed,
  );
}

class ConsoleState {
  const ConsoleState({
    required this.observedAt,
    this.tankName = 'Tank 01',
    this.temperature = 27.3,
    this.ph = 7.32,
    this.tds = 124,
    this.turbidity = 4.8,
    this.quality = ConsoleWaterQuality.normal,
    this.localConnected = true,
    this.cloudConnected = true,
    this.equipment = const ConsoleEquipmentState(),
    this.command,
    this.isSimulated = true,
  });

  final String tankName;
  final double temperature;
  final double ph;
  final double tds;
  final double turbidity;
  final DateTime observedAt;
  final ConsoleWaterQuality quality;
  final bool localConnected;
  final bool cloudConnected;
  final bool isSimulated;
  final ConsoleEquipmentState equipment;
  final ConsoleCommand? command;

  ConsoleState copyWith({
    double? ph,
    ConsoleWaterQuality? quality,
    bool? localConnected,
    bool? cloudConnected,
    DateTime? observedAt,
    ConsoleEquipmentState? equipment,
    ConsoleCommand? command,
  }) => ConsoleState(
    tankName: tankName,
    temperature: temperature,
    ph: ph ?? this.ph,
    tds: tds,
    turbidity: turbidity,
    observedAt: observedAt ?? this.observedAt,
    quality: quality ?? this.quality,
    localConnected: localConnected ?? this.localConnected,
    cloudConnected: cloudConnected ?? this.cloudConnected,
    equipment: equipment ?? this.equipment,
    command: command ?? this.command,
    isSimulated: isSimulated,
  );
}

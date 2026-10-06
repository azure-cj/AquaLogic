import 'console_command.dart';

enum ConsoleWaterQuality {
  normal,
  attention,
  critical;

  String get label => name.toUpperCase();
}

enum ConsoleLocalConnection { connecting, connected, degraded, disconnected }

class ConsoleEquipmentState {
  const ConsoleEquipmentState({
    this.lightOn = true,
    this.uvOn = true,
    this.feederRunning = false,
    this.lightConfirmed = true,
    this.uvConfirmed = true,
    this.feederConfirmed = true,
    this.pumpAStatus = 'IDLE',
    this.pumpBStatus = 'IDLE',
  });
  final bool lightOn;
  final bool uvOn;
  final bool feederRunning;
  final bool lightConfirmed;
  final bool uvConfirmed;
  final bool feederConfirmed;
  // Reported motion only: an idle motor does not mean dosing is safe.
  final String pumpAStatus;
  final String pumpBStatus;

  ConsoleEquipmentState copyWith({
    bool? lightOn,
    bool? uvOn,
    bool? feederRunning,
    bool? lightConfirmed,
    bool? uvConfirmed,
    bool? feederConfirmed,
    String? pumpAStatus,
    String? pumpBStatus,
  }) => ConsoleEquipmentState(
    lightOn: lightOn ?? this.lightOn,
    uvOn: uvOn ?? this.uvOn,
    feederRunning: feederRunning ?? this.feederRunning,
    lightConfirmed: lightConfirmed ?? this.lightConfirmed,
    uvConfirmed: uvConfirmed ?? this.uvConfirmed,
    feederConfirmed: feederConfirmed ?? this.feederConfirmed,
    pumpAStatus: pumpAStatus ?? this.pumpAStatus,
    pumpBStatus: pumpBStatus ?? this.pumpBStatus,
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
    this.localStatus,
    this.sensorStatuses = const {},
    this.connectionMessage,
    this.telemetryStale,
  });

  final String tankName;
  final double? temperature;
  final double? ph;
  final double? tds;
  final double? turbidity;

  /// Local receipt time; firmware /data contains no sample timestamp.
  final DateTime? observedAt;
  final ConsoleWaterQuality? quality;
  final bool localConnected;
  final bool? cloudConnected;
  final bool isSimulated;
  final ConsoleEquipmentState equipment;
  final ConsoleCommand? command;
  final ConsoleLocalConnection? localStatus;
  final Map<String, String> sensorStatuses;
  final String? connectionMessage;
  final bool? telemetryStale;
  ConsoleLocalConnection get connection =>
      localStatus ??
      (localConnected
          ? ConsoleLocalConnection.connected
          : ConsoleLocalConnection.disconnected);
  bool get readingsStale =>
      telemetryStale ?? connection != ConsoleLocalConnection.connected;

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
    localStatus: localStatus,
    sensorStatuses: sensorStatuses,
    connectionMessage: connectionMessage,
    telemetryStale: telemetryStale,
  );
}

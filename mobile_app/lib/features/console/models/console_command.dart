enum ConsoleCommandStatus {
  idle,
  accepted,
  running,
  completed,
  sending,
  confirming,
  confirmed,
  failed,
  rejected,
  unknown;

  String get label => name.toUpperCase();
  bool get isPending =>
      this == accepted ||
      this == running ||
      this == sending ||
      this == confirming;
}

enum ConsoleActuator { light, uv, feeder, pumpA, pumpB }

enum ConsoleAction {
  lightOn,
  lightOff,
  uvOn,
  uvOff,
  feed,
  pumpADispense,
  pumpAStop,
  pumpARetract,
  pumpARefill,
  pumpBDispense,
  pumpBStop,
  pumpBRetract,
  pumpBRefill;

  ConsoleActuator get actuator => switch (this) {
    lightOn || lightOff => ConsoleActuator.light,
    uvOn || uvOff => ConsoleActuator.uv,
    feed => ConsoleActuator.feeder,
    pumpADispense ||
    pumpAStop ||
    pumpARetract ||
    pumpARefill => ConsoleActuator.pumpA,
    _ => ConsoleActuator.pumpB,
  };
  bool get isPump =>
      actuator == ConsoleActuator.pumpA || actuator == ConsoleActuator.pumpB;
  bool get isStop => this == pumpAStop || this == pumpBStop;
  bool get isDispense => this == pumpADispense || this == pumpBDispense;
  bool get isRefill => this == pumpARefill || this == pumpBRefill;
  bool get isRetract => this == pumpARetract || this == pumpBRetract;
  String get statusPath => switch (actuator) {
    ConsoleActuator.light => '/led/status',
    ConsoleActuator.uv => '/uv/status',
    ConsoleActuator.feeder => '/feeder/status',
    ConsoleActuator.pumpA => '/syringeA/status',
    ConsoleActuator.pumpB => '/syringeB/status',
  };
  String get path => switch (this) {
    lightOn => '/led/on',
    lightOff => '/led/off',
    uvOn => '/uv/on',
    uvOff => '/uv/off',
    feed => '/feeder/feed',
    _ =>
      '${actuator == ConsoleActuator.pumpA ? '/syringeA' : '/syringeB'}/${isDispense
          ? 'dispense'
          : isStop
          ? 'stop'
          : isRefill
          ? 'refill-confirm'
          : 'retract'}',
  };
}

class ConsoleCommand {
  const ConsoleCommand({
    required this.id,
    required this.action,
    required this.status,
    required this.message,
  });

  final String id;
  final ConsoleAction action;
  final ConsoleCommandStatus status;
  final String message;

  ConsoleCommand withResult(ConsoleCommandStatus status, String message) =>
      ConsoleCommand(id: id, action: action, status: status, message: message);
}

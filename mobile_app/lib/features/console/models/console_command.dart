enum ConsoleCommandStatus {
  idle,
  accepted,
  running,
  completed,
  rejected,
  unknown;

  String get label => name.toUpperCase();
  bool get isPending => this == accepted || this == running;
}

enum ConsoleAction { lightOn, lightOff, uvOn, uvOff, feed }

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

/// Operational state of a tank. This is intentionally separate from device
/// connectivity, species suitability, and actuator command state.
enum OperationalStatus {
  normal,
  warning,
  critical,
  offline;

  String get label => switch (this) {
    OperationalStatus.normal => 'Normal',
    OperationalStatus.warning => 'Warning',
    OperationalStatus.critical => 'Critical',
    OperationalStatus.offline => 'Offline',
  };

  String get code => name;

  bool get requiresAttention => this != OperationalStatus.normal;
}

/// Advisory species-care result. It is not an operational tank status.
enum SpeciesSuitability {
  suitable,
  attention,
  unavailable;

  String get label => switch (this) {
    SpeciesSuitability.suitable => 'Suitable',
    SpeciesSuitability.attention => 'Attention',
    SpeciesSuitability.unavailable => 'Unavailable',
  };
}

/// Connectivity of a registered equipment device. It is not the tank's
/// operational status.
enum DeviceConnectionStatus {
  online,
  offline,
  disabled,
  unknown;

  String get label => switch (this) {
    DeviceConnectionStatus.online => 'Device online',
    DeviceConnectionStatus.offline => 'Device offline',
    DeviceConnectionStatus.disabled => 'Device disabled',
    DeviceConnectionStatus.unknown => 'State unknown',
  };
}

/// Lifecycle of an actuator command, including the deliberately distinct
/// ambiguous outcome state.
enum CommandStatus {
  queued,
  executing,
  succeeded,
  failed,
  expired,
  outcomeUnknown;

  String get label => switch (this) {
    CommandStatus.queued => 'Queued',
    CommandStatus.executing => 'Executing',
    CommandStatus.succeeded => 'Succeeded',
    CommandStatus.failed => 'Failed',
    CommandStatus.expired => 'Expired',
    CommandStatus.outcomeUnknown => 'Outcome unknown',
  };
}

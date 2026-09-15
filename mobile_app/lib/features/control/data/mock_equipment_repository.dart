import 'package:aqualogic/features/control/models/equipment_models.dart';
import 'package:aqualogic/shared/models/aqualogic_status.dart';

abstract class EquipmentRepository {
  EquipmentOverview load({required String tankId});
}

/// Deterministic equipment fixtures for the Owner UI. Commands are simulated
/// by the screen so no physical device or HTTP boundary is introduced.
class MockEquipmentRepository implements EquipmentRepository {
  const MockEquipmentRepository();

  @override
  EquipmentOverview load({required String tankId}) {
    return const EquipmentOverview(
      devices: [
        EquipmentDevice(
          id: 'uv-sterilizer',
          name: 'UV Sterilizer',
          subtitle: 'Reduces algae and pathogens',
          kind: EquipmentKind.uv,
          powerState: EquipmentPowerState.on,
          connection: DeviceConnectionStatus.online,
          scheduleLabel: 'Daily 02:00–02:45',
          lastActionLabel: 'Turned on this morning',
        ),
        EquipmentDevice(
          id: 'led-lighting',
          name: 'LED Lighting',
          subtitle: 'Maintains the daily light rhythm',
          kind: EquipmentKind.led,
          powerState: EquipmentPowerState.off,
          connection: DeviceConnectionStatus.online,
          scheduleLabel: 'Next run at 07:00',
          lastActionLabel: 'Turned off at 19:00',
        ),
        EquipmentDevice(
          id: 'automatic-feeder',
          name: 'Automatic Feeder',
          subtitle: 'Runs scheduled feed cycles',
          kind: EquipmentKind.feeder,
          powerState: EquipmentPowerState.ready,
          connection: DeviceConnectionStatus.online,
          scheduleLabel: 'Next feed at 14:00',
          lastActionLabel: 'Feed completed at 08:30',
        ),
        EquipmentDevice(
          id: 'pump-a',
          name: 'Pump A',
          subtitle: 'Guarded manual maintenance test',
          kind: EquipmentKind.pumpA,
          powerState: EquipmentPowerState.idle,
          connection: DeviceConnectionStatus.online,
          scheduleLabel: 'Manual test only',
          lastActionLabel: 'No recent command',
        ),
        EquipmentDevice(
          id: 'pump-b',
          name: 'Pump B',
          subtitle: 'Guarded manual maintenance test',
          kind: EquipmentKind.pumpB,
          powerState: EquipmentPowerState.unknown,
          connection: DeviceConnectionStatus.offline,
          scheduleLabel: 'Manual test only',
          lastActionLabel: 'Bridge last seen earlier',
        ),
      ],
      commandHistory: [
        CommandRecord(
          id: 'command-queued',
          equipmentId: 'automatic-feeder',
          equipmentName: 'Automatic Feeder',
          actionLabel: 'Feed now',
          status: CommandStatus.queued,
          timeLabel: '8:40 AM',
        ),
        CommandRecord(
          id: 'command-executing',
          equipmentId: 'led-lighting',
          equipmentName: 'LED Lighting',
          actionLabel: 'Turn on',
          status: CommandStatus.executing,
          timeLabel: '8:36 AM',
        ),
        CommandRecord(
          id: 'command-succeeded',
          equipmentId: 'automatic-feeder',
          equipmentName: 'Automatic Feeder',
          actionLabel: 'Feed now',
          status: CommandStatus.succeeded,
          timeLabel: '8:32 AM',
        ),
        CommandRecord(
          id: 'command-failed',
          equipmentId: 'uv-sterilizer',
          equipmentName: 'UV Sterilizer',
          actionLabel: 'Turn off',
          status: CommandStatus.failed,
          timeLabel: '8:24 AM',
        ),
        CommandRecord(
          id: 'command-expired',
          equipmentId: 'pump-b',
          equipmentName: 'Pump B',
          actionLabel: 'Run manual test',
          status: CommandStatus.expired,
          timeLabel: '8:18 AM',
        ),
        CommandRecord(
          id: 'command-unknown',
          equipmentId: 'pump-a',
          equipmentName: 'Pump A',
          actionLabel: 'Run manual test',
          status: CommandStatus.outcomeUnknown,
          timeLabel: '8:15 AM',
          detail: 'Confirmation was not received after dispatch.',
        ),
      ],
    );
  }
}

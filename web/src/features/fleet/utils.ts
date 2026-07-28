import type { Alert, FleetTank } from '@/shared/api/models';

export function fleetCounts(tanks: FleetTank[]) {
  return tanks.reduce(
    (counts, tank) => {
      counts.total += 1;
      counts[tank.status] += 1;
      return counts;
    },
    { total: 0, normal: 0, warning: 0, critical: 0, offline: 0 },
  );
}

export function tankNameForAlert(
  alert: Alert,
  tanks: Array<Pick<FleetTank, 'id' | 'name'>>,
) {
  return tanks.find((tank) => tank.id === alert.tank_id)?.name ?? `Tank ${alert.tank_id}`;
}

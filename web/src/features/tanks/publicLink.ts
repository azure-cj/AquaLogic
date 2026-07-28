import type { Tank } from '@/shared/api/models';

export const publicTankUrl = (tank: Tank) => `${window.location.origin}/tank/${tank.public_id}`;

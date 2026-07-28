type ModuleLoader<T> = () => Promise<T>;

function once<T>(loader: ModuleLoader<T>): ModuleLoader<T> {
  let pending: Promise<T> | undefined;
  return () => {
    pending ??= loader();
    return pending;
  };
}

export const pageLoaders = {
  login: once(() => import('@/features/auth/LoginPage')),
  changePassword: once(() => import('@/features/auth/ChangePasswordPage')),
  fleet: once(() => import('@/features/fleet/FleetPage')),
  alerts: once(() => import('@/features/alerts/AlertsPage')),
  tanks: once(() => import('@/features/tanks/TanksPage')),
  tankDetail: once(() => import('@/features/tanks/TankDetailPage')),
  fish: once(() => import('@/features/fish/FishPage')),
  customers: once(() => import('@/features/customers/CustomersPage')),
  analytics: once(() => import('@/features/analytics/AnalyticsPage')),
  staff: once(() => import('@/features/staff/StaffPage')),
  thresholds: once(() => import('@/features/thresholds/ThresholdsPage')),
  publicTank: once(() =>
    import('@/features/public-tank/PublicTankPage').then((module) => ({
      default: module.PublicTank,
    })),
  ),
};

const adminLoaders = {
  '/admin/fleet': pageLoaders.fleet,
  '/admin/alerts': pageLoaders.alerts,
  '/admin/tanks': pageLoaders.tanks,
  '/admin/tanks/:tankId': pageLoaders.tankDetail,
  '/admin/fish': pageLoaders.fish,
  '/admin/customers': pageLoaders.customers,
  '/admin/analytics': pageLoaders.analytics,
  '/admin/staff': pageLoaders.staff,
  '/admin/settings/thresholds': pageLoaders.thresholds,
} as const;

export function prefetchAdminRoute(path: string) {
  const normalized = path.startsWith('/admin/tanks/')
    ? '/admin/tanks/:tankId'
    : path;
  const loader = adminLoaders[normalized as keyof typeof adminLoaders];
  return loader?.();
}

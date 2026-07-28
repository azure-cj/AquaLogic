import { AppRouter, adminRoutePaths } from '@/app/router';
import { render, screen } from '@testing-library/react';
import { MemoryRouter, Outlet } from 'react-router-dom';
import { describe, expect, it, vi } from 'vitest';

vi.mock('@/layouts/admin/AdminShell', () => ({
  default: () => <Outlet />,
}));
vi.mock('@/features/auth/LoginPage', () => ({
  default: () => <div>Login route</div>,
}));
vi.mock('@/features/auth/ChangePasswordPage', () => ({
  default: () => <div>Password route</div>,
}));
vi.mock('@/features/auth/SetupPasswordPage', () => ({
  default: () => <div>Setup password route</div>,
}));
vi.mock('@/features/auth/SecurityPage', () => ({
  default: () => <div>Security route</div>,
}));
vi.mock('@/features/fleet/FleetPage', () => ({
  default: () => <div>Fleet route</div>,
}));
vi.mock('@/features/alerts/AlertsPage', () => ({
  default: () => <div>Alerts route</div>,
}));
vi.mock('@/features/tanks/TanksPage', () => ({
  default: () => <div>Tanks route</div>,
}));
vi.mock('@/features/tanks/TankDetailPage', () => ({
  default: () => <div>Tank detail route</div>,
}));
vi.mock('@/features/fish/FishPage', () => ({
  default: () => <div>Fish route</div>,
}));
vi.mock('@/features/customers/CustomersPage', () => ({
  default: () => <div>Customers route</div>,
}));
vi.mock('@/features/analytics/AnalyticsPage', () => ({
  default: () => <div>Analytics route</div>,
}));
vi.mock('@/features/staff/StaffPage', () => ({
  default: () => <div>Staff route</div>,
}));
vi.mock('@/features/thresholds/ThresholdsPage', () => ({
  default: () => <div>Thresholds route</div>,
}));
vi.mock('@/features/public-tank/PublicTankPage', () => ({
  PublicTank: () => <div>Public tank route</div>,
}));

const routes = [
  ['/admin/fleet', 'Fleet route'],
  ['/admin/alerts', 'Alerts route'],
  ['/admin/tanks', 'Tanks route'],
  ['/admin/tanks/42', 'Tank detail route'],
  ['/admin/fish', 'Fish route'],
  ['/admin/customers', 'Customers route'],
  ['/admin/security', 'Security route'],
  ['/admin/analytics', 'Analytics route'],
  ['/admin/staff', 'Staff route'],
  ['/admin/settings/thresholds', 'Thresholds route'],
  ['/admin/login', 'Login route'],
  ['/admin/change-password', 'Password route'],
  ['/admin/setup-password', 'Setup password route'],
  ['/tank/public-id', 'Public tank route'],
] as const;

describe('application router', () => {
  it('keeps the complete admin route contract', () => {
    expect(adminRoutePaths).toEqual([
      'fleet',
      'alerts',
      'tanks',
      'tanks/:tankId',
      'fish',
      'customers',
      'security',
      'analytics',
      'staff',
      'settings/thresholds',
    ]);
  });

  it.each(routes)('resolves %s through its lazy page module', async (path, label) => {
    render(
      <MemoryRouter initialEntries={[path]}>
        <AppRouter />
      </MemoryRouter>,
    );
    expect(await screen.findByText(label)).toBeInTheDocument();
  });
});

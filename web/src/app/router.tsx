import AdminShell from '@/layouts/admin/AdminShell';
import { RouteLoading } from '@/shared/components/RouteLoading';
import { lazy, Suspense } from 'react';
import { Navigate, Route, Routes } from 'react-router-dom';
import { pageLoaders } from './route-loaders';

const LoginPage = lazy(pageLoaders.login);
const ChangePasswordPage = lazy(pageLoaders.changePassword);
const SetupPasswordPage = lazy(pageLoaders.setupPassword);
const FleetPage = lazy(pageLoaders.fleet);
const AlertsPage = lazy(pageLoaders.alerts);
const TanksPage = lazy(pageLoaders.tanks);
const TankDetailPage = lazy(pageLoaders.tankDetail);
const FishPage = lazy(pageLoaders.fish);
const CustomersPage = lazy(pageLoaders.customers);
const AnalyticsPage = lazy(pageLoaders.analytics);
const StaffPage = lazy(pageLoaders.staff);
const ThresholdsPage = lazy(pageLoaders.thresholds);
const SecurityPage = lazy(pageLoaders.security);
const PublicTankPage = lazy(pageLoaders.publicTank);

export const adminRoutePaths = [
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
] as const;

export function AppRouter() {
  return (
    <Routes>
      <Route
        path="/tank/:publicId"
        element={
          <Suspense fallback={<RouteLoading />}>
            <PublicTankPage />
          </Suspense>
        }
      />
      <Route
        path="/admin/login"
        element={
          <Suspense fallback={<RouteLoading />}>
            <LoginPage />
          </Suspense>
        }
      />
      <Route
        path="/admin/change-password"
        element={
          <Suspense fallback={<RouteLoading />}>
            <ChangePasswordPage />
          </Suspense>
        }
      />
      <Route
        path="/admin/setup-password"
        element={
          <Suspense fallback={<RouteLoading />}>
            <SetupPasswordPage />
          </Suspense>
        }
      />
      <Route path="/admin" element={<AdminShell />}>
        <Route index element={<Navigate to="fleet" replace />} />
        <Route path="fleet" element={<FleetPage />} />
        <Route path="alerts" element={<AlertsPage />} />
        <Route path="tanks" element={<TanksPage />} />
        <Route path="tanks/:tankId" element={<TankDetailPage />} />
        <Route path="fish" element={<FishPage />} />
        <Route path="customers" element={<CustomersPage />} />
        <Route path="security" element={<SecurityPage />} />
        <Route path="analytics" element={<AnalyticsPage />} />
        <Route path="staff" element={<StaffPage />} />
        <Route path="settings/thresholds" element={<ThresholdsPage />} />
      </Route>
      <Route path="*" element={<Navigate to="/admin" replace />} />
    </Routes>
  );
}

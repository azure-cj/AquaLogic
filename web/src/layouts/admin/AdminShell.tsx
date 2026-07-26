import { api, clearSession } from '@/shared/api/client';
import { prefetchAdminRoute } from '@/app/route-loaders';
import type { Alert } from '@/shared/api/models';
import {
  LoadingState
} from '@/shared/components/admin-ui';
import {
  initials
} from '@/shared/utils/formatting';
import { useQuery } from '@tanstack/react-query';
import type { LucideIcon } from 'lucide-react';
import {
  BarChart3,
  BellRing,
  Droplets,
  FishSymbol,
  LayoutDashboard,
  LogOut,
  Menu,
  Plus,
  SlidersHorizontal,
  UserRoundCog,
  UsersRound
} from 'lucide-react';
import {
  Suspense,
  useEffect,
  useState
} from 'react';
import {
  Link,
  Navigate,
  NavLink,
  Outlet,
  useLocation,
  useNavigate
} from 'react-router-dom';

import { Brand } from '@/shared/components/Brand';
import { RouteLoading } from '@/shared/components/RouteLoading';
import { useMe } from '@/shared/hooks/useMe';
import './styles.css';

const navigation: Array<{
  label: string;
  items: Array<{
    to: string;
    label: string;
    icon: LucideIcon;
    badge?: boolean;
    adminOnly?: boolean;
  }>;
}> = [
    {
      label: 'Monitor',
      items: [
        { to: '/admin/fleet', label: 'Fleet overview', icon: LayoutDashboard },
        { to: '/admin/alerts', label: 'Alerts', icon: BellRing, badge: true },
        { to: '/admin/analytics', label: 'Analytics', icon: BarChart3 },
      ],
    },
    {
      label: 'Manage',
      items: [
        { to: '/admin/tanks', label: 'Tanks', icon: Droplets },
        { to: '/admin/fish', label: 'Fish species', icon: FishSymbol },
        { to: '/admin/customers', label: 'Customers', icon: UsersRound },
        { to: '/admin/staff', label: 'Staff & roles', icon: UserRoundCog, adminOnly: true },
      ],
    },
    {
      label: 'System',
      items: [
        {
          to: '/admin/settings/thresholds',
          label: 'Thresholds',
          icon: SlidersHorizontal,
          adminOnly: true,
        },
      ],
    },
  ];

const pageTitles: Record<string, string> = {
  fleet: 'Fleet command center',
  alerts: 'Alert history',
  tanks: 'Tank management',
  fish: 'Fish species',
  customers: 'Customer management',
  analytics: 'Fleet analytics',
  staff: 'Staff & roles',
  settings: 'System thresholds',
};

export function AdminShell() {
  const nav = useNavigate();
  const location = useLocation();
  const me = useMe();
  const [mobileNav, setMobileNav] = useState(false);
  const alertQuery = useQuery({
    queryKey: ['alerts', 'nav-unresolved'],
    queryFn: () => api<Alert[]>('/alerts/history?resolved=false'),
    enabled: Boolean(me.data),
    refetchInterval: 30_000,
  });

  useEffect(() => {
    const unauthorized = () => nav('/admin/login');
    window.addEventListener('aqualogic:unauthorized', unauthorized);
    return () => window.removeEventListener('aqualogic:unauthorized', unauthorized);
  }, [nav]);

  useEffect(() => setMobileNav(false), [location.pathname]);

  if (me.isLoading) {
    return (
      <main className="session-check">
        <Brand />
        <LoadingState label="Checking your secure session…" />
      </main>
    );
  }
  if (me.isError) return <Navigate to="/admin/login" replace />;
  if (me.data!.must_change_password) return <Navigate to="/admin/change-password" replace />;

  const admin = me.data!.role === 'admin';
  const segment = location.pathname.split('/')[2] || 'fleet';

  return (
    <div className={`admin-shell ${mobileNav ? 'nav-open' : ''}`}>
      <button
        className="nav-scrim"
        type="button"
        aria-label="Close navigation"
        onClick={() => setMobileNav(false)}
      />
      <aside className="admin-sidebar">
        <Link className="sidebar-brand" to="/admin/fleet" aria-label="AquaLogic fleet overview">
          <Brand />
        </Link>
        <nav className="sidebar-nav" aria-label="Admin navigation">
          {navigation.map((group) => {
            const items = group.items.filter((item) => !item.adminOnly || admin);
            if (!items.length) return null;
            return (
              <div className="nav-group" key={group.label}>
                <p>{group.label}</p>
                {items.map(({ to, label, icon: Icon, badge }) => (
                  <NavLink
                    key={to}
                    to={to}
                    className={({ isActive }) => (isActive ? 'active' : undefined)}
                    onPointerEnter={() => void prefetchAdminRoute(to)}
                    onFocus={() => void prefetchAdminRoute(to)}
                    onTouchStart={() => void prefetchAdminRoute(to)}
                  >
                    <Icon size={18} aria-hidden="true" />
                    <span>{label}</span>
                    {badge && Boolean(alertQuery.data?.length) && (
                      <b className="nav-badge" aria-label={`${alertQuery.data!.length} unresolved`}>
                        {alertQuery.data!.length > 99 ? '99+' : alertQuery.data!.length}
                      </b>
                    )}
                  </NavLink>
                ))}
              </div>
            );
          })}
        </nav>
        <div className="sidebar-user">
          <span className="avatar" aria-hidden="true">
            {initials(me.data!.name)}
          </span>
          <span>
            <strong>{me.data!.name}</strong>
            <small>{me.data!.role}</small>
          </span>
          <button
            className="icon-button sidebar-signout"
            type="button"
            aria-label="Sign out"
            onClick={() => {
              clearSession();
              nav('/admin/login');
            }}
          >
            <LogOut size={18} />
          </button>
        </div>
      </aside>
      <main className="admin-main">
        <header className="admin-topbar">
          <button
            className="icon-button mobile-menu"
            type="button"
            aria-label="Open navigation"
            aria-expanded={mobileNav}
            onClick={() => setMobileNav(true)}
          >
            <Menu size={21} />
          </button>
          <div>
            <p className="eyebrow">Live operations</p>
            <strong>{pageTitles[segment] ?? 'AquaLogic admin'}</strong>
          </div>
          {segment === 'fleet' && (
            <Link className="button button-primary topbar-primary-action" to="/admin/tanks">
              <Plus size={17} />
              <span>Add tank</span>
            </Link>
          )}
          <div className="topbar-status">
            <span className="live-dot" aria-hidden="true" />
            <span>Live data</span>
            <small>30 sec refresh</small>
          </div>
          <span className="topbar-avatar avatar" aria-hidden="true">
            {initials(me.data!.name)}
          </span>
        </header>
        <div className="admin-content">
          <Suspense
            fallback={
              <RouteLoading
                variant="content"
                label="Loading dashboard page…"
              />
            }
          >
            <Outlet />
          </Suspense>
        </div>
      </main>
    </div>
  );
}

export default AdminShell;

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
import {
  ChevronDown,
  LogOut,
  Menu,
} from 'lucide-react';
import {
  Suspense,
  useEffect,
  useLayoutEffect,
  useRef,
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
import {
  adminNavigation,
  adminNavigationItemCount,
  NAVIGATION_FLAT_ITEM_LIMIT,
  type AdminNavigationItem,
} from './navigation';
import './styles.css';

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
  const [openCluster, setOpenCluster] = useState<string | null>(null);
  const desktopNavRef = useRef<HTMLElement>(null);
  const adminMainRef = useRef<HTMLElement>(null);
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

  useEffect(() => {
    setMobileNav(false);
    setOpenCluster(null);
  }, [location.pathname]);

  useLayoutEffect(() => {
    // React Router preserves document scroll during client-side navigation.
    // Reset only the horizontal axis before the new route paints.
    if (document.scrollingElement) document.scrollingElement.scrollLeft = 0;
    document.documentElement.scrollLeft = 0;
    document.body.scrollLeft = 0;
    if (adminMainRef.current) adminMainRef.current.scrollLeft = 0;
  }, [location.pathname]);

  useEffect(() => {
    if (!openCluster) return undefined;

    const closeOnOutsidePointer = (event: PointerEvent) => {
      if (!desktopNavRef.current?.contains(event.target as Node)) setOpenCluster(null);
    };
    const closeOnEscape = (event: KeyboardEvent) => {
      if (event.key === 'Escape') setOpenCluster(null);
    };

    document.addEventListener('pointerdown', closeOnOutsidePointer);
    document.addEventListener('keydown', closeOnEscape);
    return () => {
      document.removeEventListener('pointerdown', closeOnOutsidePointer);
      document.removeEventListener('keydown', closeOnEscape);
    };
  }, [openCluster]);

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
  const isTankDetail = /^\/admin\/tanks\/\d+$/.test(location.pathname);
  const visibleNavigation = adminNavigation
    .map((group) => ({
      ...group,
      items: group.items.filter((item) => !item.adminOnly || admin),
    }))
    .filter((group) => group.items.length);
  const clusteredByCount = adminNavigationItemCount > NAVIGATION_FLAT_ITEM_LIMIT;
  const renderNavigationLink = (item: AdminNavigationItem, className: string, iconSize: number) => {
    const Icon = item.icon;
    return (
      <NavLink
        key={item.to}
        to={item.to}
        className={({ isActive }) => (isActive ? `${className} active` : className)}
        onPointerEnter={() => void prefetchAdminRoute(item.to)}
        onFocus={() => void prefetchAdminRoute(item.to)}
        onTouchStart={() => void prefetchAdminRoute(item.to)}
      >
        <Icon size={iconSize} aria-hidden="true" />
        <span>{item.label}</span>
        {item.badge === 'unresolved-alerts' && Boolean(alertQuery.data?.length) && (
          <b className="nav-badge" aria-label={`${alertQuery.data!.length} unresolved`}>
            {alertQuery.data!.length > 99 ? '99+' : alertQuery.data!.length}
          </b>
        )}
      </NavLink>
    );
  };

  return (
    <div className={`admin-shell ${mobileNav ? 'nav-open' : ''}`}>
      <button
        className="nav-scrim"
        type="button"
        aria-label="Close navigation"
        onClick={() => setMobileNav(false)}
      />

      <div className="floating-island-wrapper">
        <header className="floating-island">
          <Link className="island-brand" to="/admin/fleet" aria-label="AquaLogic fleet overview">
            <Brand />
          </Link>

          <nav
            className={`island-nav ${clusteredByCount ? 'island-nav-count-clustered' : ''}`}
            aria-label="Admin navigation"
            ref={desktopNavRef}
          >
            {visibleNavigation.map((group) => {
              const isOpen = openCluster === group.id;
              const isActive = group.items.some((item) => location.pathname === item.to);
              return (
                <div
                  className={`island-nav-group ${isOpen ? 'cluster-open' : ''} ${isActive ? 'cluster-active' : ''}`}
                  key={group.id}
                >
                  <button
                    className="cluster-toggle"
                    type="button"
                    aria-expanded={isOpen}
                    aria-controls={`admin-navigation-${group.id}`}
                    onClick={() => setOpenCluster(isOpen ? null : group.id)}
                  >
                    <span>{group.label}</span>
                    <ChevronDown size={15} aria-hidden="true" />
                  </button>
                  <div className="cluster-menu" id={`admin-navigation-${group.id}`}>
                    {group.items.map((item) => renderNavigationLink(item, 'nav-pill', 16))}
                  </div>
                </div>
              );
            })}
          </nav>

          <div className="island-actions">
            <div className="island-user-menu">
              <span className="avatar" aria-hidden="true">
                {initials(me.data!.name)}
              </span>
              <div className="user-details">
                <strong>{me.data!.name}</strong>
                <small>{me.data!.role}</small>
              </div>
              <button
                className="icon-button island-signout"
                type="button"
                aria-label="Sign out"
                onClick={() => {
                  clearSession();
                  nav('/admin/login');
                }}
              >
                <LogOut size={16} />
              </button>
            </div>
            <button
              className="icon-button mobile-menu"
              type="button"
              aria-label="Open navigation"
              aria-expanded={mobileNav}
              onClick={() => setMobileNav(!mobileNav)}
            >
              <Menu size={20} />
            </button>
          </div>
        </header>
      </div>

      <aside className="mobile-nav-drawer" aria-label="Mobile navigation drawer">
        <div className="mobile-drawer-header">
          <p className="eyebrow">Live operations</p>
          <strong>{pageTitles[segment] ?? 'AquaLogic admin'}</strong>
        </div>
        <nav className="mobile-drawer-nav" aria-label="Mobile menu navigation">
          {visibleNavigation.map((group) => {
            return (
              <div className="mobile-nav-group" key={group.id}>
                <p>{group.label}</p>
                {group.items.map((item) => renderNavigationLink(item, 'mobile-nav-link', 18))}
              </div>
            );
          })}
        </nav>
        <div className="mobile-drawer-user">
          <span className="avatar" aria-hidden="true">
            {initials(me.data!.name)}
          </span>
          <div className="user-info">
            <strong>{me.data!.name}</strong>
            <small>{me.data!.role}</small>
          </div>
          <button
            className="icon-button mobile-signout"
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

      <main className="admin-main" ref={adminMainRef}>
        {!isTankDetail && (
          <div className="admin-context-header">
            <div>
              <p className="eyebrow">Live operations</p>
              <h1 className="page-title">{pageTitles[segment] ?? 'AquaLogic admin'}</h1>
            </div>
          </div>
        )}
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

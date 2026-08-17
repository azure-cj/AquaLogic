import type { LucideIcon } from 'lucide-react';
import {
  BarChart3,
  BellRing,
  Droplets,
  FishSymbol,
  LayoutDashboard,
  Power,
  SlidersHorizontal,
  UserRoundCog,
  UsersRound,
} from 'lucide-react';

export type AdminNavigationItem = {
  to: string;
  label: string;
  icon: LucideIcon;
  badge?: 'unresolved-alerts';
  adminOnly?: boolean;
};

export type AdminNavigationGroup = {
  id: 'monitor' | 'manage' | 'configure';
  label: string;
  items: AdminNavigationItem[];
};

export const NAVIGATION_FLAT_ITEM_LIMIT = 9;

export const adminNavigation: AdminNavigationGroup[] = [
  {
    id: 'monitor',
    label: 'Monitor',
    items: [
      { to: '/admin/fleet', label: 'Fleet overview', icon: LayoutDashboard },
      { to: '/admin/alerts', label: 'Alerts', icon: BellRing, badge: 'unresolved-alerts' },
      { to: '/admin/analytics', label: 'Analytics', icon: BarChart3 },
    ],
  },
  {
    id: 'manage',
    label: 'Manage',
    items: [
      { to: '/admin/tanks', label: 'Tanks', icon: Droplets },
      { to: '/admin/fish', label: 'Fish species', icon: FishSymbol },
      { to: '/admin/customers', label: 'Customers', icon: UsersRound },
      { to: '/admin/account', label: 'Account center', icon: UserRoundCog },
    ],
  },
  {
    id: 'configure',
    label: 'Configure',
    items: [
      {
        to: '/admin/actuators',
        label: 'Actuators',
        icon: Power,
        adminOnly: true,
      },
      {
        to: '/admin/settings/thresholds',
        label: 'Thresholds',
        icon: SlidersHorizontal,
        adminOnly: true,
      },
    ],
  },
];

export const adminNavigationItemCount = adminNavigation.reduce(
  (count, group) => count + group.items.length,
  0,
);

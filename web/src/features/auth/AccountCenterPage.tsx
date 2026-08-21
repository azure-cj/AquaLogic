import {
  Activity,
  CheckCircle2,
  ChevronDown,
  ChevronRight,
  Clock3,
  KeyRound,
  ShieldCheck,
  UserRoundCog,
  Users,
} from 'lucide-react';
import { useQuery } from '@tanstack/react-query';
import { useEffect, useRef, useState } from 'react';
import { Link } from 'react-router-dom';

import { api, SecurityAuditEvent, User } from '@/shared/api/client';
import { LifecycleBadge, PageHeader, Panel } from '@/shared/components/admin-ui';
import { useMe } from '@/shared/hooks/useMe';
import { initials } from '@/shared/utils/formatting';
import './account-center.css';

function formatDate(value?: string | null) {
  if (!value) return 'Not available';
  return new Intl.DateTimeFormat(undefined, { dateStyle: 'medium' }).format(new Date(value));
}

function accountStatus(user?: User): 'active' | 'setup_required' | 'inactive' {
  if (!user?.is_active) return 'inactive';
  if (user.must_change_password) return 'setup_required';
  return 'active';
}

function capabilities(role?: User['role']) {
  if (role === 'admin') {
    return [
      'Everything available to staff, including fleet, tanks, readings, alerts, analytics, fish, customers, and thresholds.',
      'Resolve alerts and manage species assignments across tanks.',
      'Manage staff accounts, roles, account status, sessions, and security audit activity.',
    ];
  }
  return [
    'Read fleet, tanks, readings, alerts, analytics, fish, customers, and thresholds.',
    'Resolve alerts and manage species assignments across tanks.',
    'Manage your own password and signed-in sessions; administrator security controls are not available.',
  ];
}

function AccessPopover({ role }: { role?: User['role']; }) {
  const [open, setOpen] = useState(false);
  const [hovered, setHovered] = useState(false);
  const popoverRef = useRef<HTMLDivElement>(null);
  const visible = open || hovered;
  const title = 'What you can access';

  useEffect(() => {
    if (!visible) return;
    const handlePointerDown = (event: PointerEvent) => {
      if (!popoverRef.current?.contains(event.target as Node)) setOpen(false);
    };
    document.addEventListener('pointerdown', handlePointerDown);
    return () => document.removeEventListener('pointerdown', handlePointerDown);
  }, [visible]);

  return (
    <div
      className="account-access-popover"
      ref={popoverRef}
      onMouseEnter={() => setHovered(true)}
      onMouseLeave={() => setHovered(false)}
      onBlur={(event) => {
        if (!popoverRef.current?.contains(event.relatedTarget as Node | null)) setOpen(false);
      }}
    >
      <button
        className="account-access-trigger"
        type="button"
        aria-expanded={visible}
        aria-controls="account-access-popover"
        onClick={() => setOpen((current) => !current)}
        onFocus={() => setOpen(true)}
        onKeyDown={(event) => {
          if (event.key === 'Escape') {
            event.preventDefault();
            setOpen(false);
          }
        }}
      >
        <ShieldCheck size={16} aria-hidden="true" />
        <span>{title}</span>
        <ChevronDown className="account-access-trigger-chevron" size={15} aria-hidden="true" />
      </button>
      {visible && (
        <div className="account-access-popover-panel" id="account-access-popover" role="dialog" aria-label={title}>
          <div className="account-access-popover-heading">
            <strong>{title}</strong>
            <span>Your {role === 'admin' ? 'administrator' : 'staff'} role determines these capabilities.</span>
          </div>
          <ul className="account-capability-list">
            {capabilities(role).map((capability) => (
              <li key={capability}><CheckCircle2 size={17} aria-hidden="true" /><span>{capability}</span></li>
            ))}
          </ul>
        </div>
      )}
    </div>
  );
}

function AccountDestination({
  to,
  title,
  description,
  icon: Icon,
}: {
  to: string;
  title: string;
  description: string;
  icon: typeof KeyRound;
}) {
  return (
    <Link className="account-destination" to={to}>
      <span className="account-destination-icon" aria-hidden="true">
        <Icon size={21} />
      </span>
      <span className="account-destination-copy">
        <strong>{title}</strong>
        <span>{description}</span>
      </span>
      <ChevronRight className="account-destination-arrow" size={19} aria-hidden="true" />
    </Link>
  );
}

function MetricCard({ label, value, description, icon: Icon }: {
  label: string;
  value: string | number;
  description: string;
  icon: typeof Users;
}) {
  return (
    <article className="account-metric-card">
      <span className="account-metric-icon" aria-hidden="true"><Icon size={17} /></span>
      <span className="account-metric-value">{value}</span>
      <strong>{label}</strong>
      <small>{description}</small>
    </article>
  );
}

export default function AccountCenterPage() {
  const me = useMe();
  const isAdmin = me.data?.role === 'admin';
  const users = useQuery({
    queryKey: ['users'],
    queryFn: () => api<User[]>('/users'),
    enabled: isAdmin,
  });
  const recentAudit = useQuery({
    queryKey: ['security-audit-events', 'account-summary'],
    queryFn: () => api<SecurityAuditEvent[]>('/security/audit-events?limit=5'),
    enabled: isAdmin,
  });
  const status = accountStatus(me.data);
  const team = users.data ?? [];

  return (
    <section className="account-center">
      <PageHeader
        eyebrow="Administration"
        title="Account center"
        description={isAdmin ? 'Understand your access and manage the team lifecycle.' : 'Understand your access and manage your personal security.'}
        actions={<AccessPopover role={me.data?.role} />}
      />

      <div className="account-overview-grid">
        <Panel title="Your account" description="A quick view of the identity and security state used for this session.">
          <div className="account-profile-card">
            <span className="account-profile-avatar avatar">{initials(me.data?.name ?? 'AquaLogic user')}</span>
            <div className="account-profile-identity">
              <strong>{me.data?.name ?? 'Loading account'}</strong>
              <span>{me.data?.email ?? 'Loading email'}</span>
              <div className="account-profile-badges">
                <LifecycleBadge status={status} />
                <span className="account-role-chip">{me.data?.role === 'admin' ? 'Administrator' : 'Staff'}</span>
              </div>
            </div>
          </div>
          <dl className="account-meta-grid">
            <div><dt>Account created</dt><dd>{formatDate(me.data?.created_at)}</dd></div>
            <div><dt>Password status</dt><dd>{me.data?.must_change_password ? 'Setup required' : 'Password configured'}</dd></div>
            <div><dt>Role</dt><dd>{me.data?.role === 'admin' ? 'Administrator' : 'Staff'}</dd></div>
            <div><dt>Account state</dt><dd>{status === 'active' ? 'Active' : status === 'setup_required' ? 'Password setup required' : 'Inactive'}</dd></div>
          </dl>
          <Link className="account-inline-link" to="/admin/change-password">
            <KeyRound size={16} aria-hidden="true" /> Change password <ChevronRight size={15} aria-hidden="true" />
          </Link>
        </Panel>

      </div>

      {isAdmin && (
        <Panel className="account-team-panel" title="Team access snapshot" description="Use Staff & roles for account-by-account lifecycle actions.">
          <div className="account-metric-grid">
            <MetricCard label="Active team members" value={team.filter((user) => user.account_status === 'active').length} description="Ready for normal access" icon={Users} />
            <MetricCard label="Pending setup" value={team.filter((user) => user.account_status === 'setup_required').length} description="Waiting for a password" icon={Clock3} />
            <MetricCard label="Inactive accounts" value={team.filter((user) => user.account_status === 'inactive').length} description="Access currently disabled" icon={ShieldCheck} />
            <MetricCard label="Administrators / staff" value={`${team.filter((user) => user.role === 'admin').length} / ${team.filter((user) => user.role === 'staff').length}`} description="Current role distribution" icon={UserRoundCog} />
            <MetricCard label="Recent security activity" value={recentAudit.data?.length ?? 0} description="Events in the latest feed" icon={Activity} />
          </div>
        </Panel>
      )}

      <div className="account-center-grid">
        <Panel title="Your security" description="Manage the sessions connected to your own account.">
          <AccountDestination
            to="/admin/security"
            title="Security"
            description="Review signed-in devices, revoke access you do not recognize, and review account activity when permitted."
            icon={KeyRound}
          />
        </Panel>

        {isAdmin && (
          <Panel title="Administration" description="Manage access for the AquaLogic team.">
            <AccountDestination
              to="/admin/staff"
              title="Staff & roles"
              description="Search account lifecycle state, inspect sessions, review activity, and manage roles."
              icon={UserRoundCog}
            />
          </Panel>
        )}
      </div>
    </section>
  );
}

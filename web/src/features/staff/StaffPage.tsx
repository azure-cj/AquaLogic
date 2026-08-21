import { useQuery, useQueryClient } from '@tanstack/react-query';
import {
  ArrowLeft,
  CheckCircle2,
  Clipboard,
  ChevronDown,
  ChevronUp,
  Clock3,
  KeyRound,
  Laptop,
  ListFilter,
  LogOut,
  Search,
  ShieldCheck,
  UserPlus,
  Users,
} from 'lucide-react';
import { type FormEvent, useMemo, useState } from 'react';
import { Link } from 'react-router-dom';

import { api, AdminSession, SecurityAuditEvent, User } from '@/shared/api/client';
import {
  ConfirmDialog,
  Drawer,
  EmptyState,
  ErrorState,
  LifecycleBadge,
  LoadingState,
  Notice,
  PageHeader,
  Panel,
} from '@/shared/components/admin-ui';
import { useMe } from '@/shared/hooks/useMe';
import { initials } from '@/shared/utils/formatting';
import './styles.css';

type AccountStatus = 'active' | 'setup_required' | 'inactive';
type ActivityFilter = 'all' | 'recent' | 'stale' | 'never';
type AdminUser = User & {
  created_at: string;
  account_status: AccountStatus;
  password_changed_at: string | null;
  active_session_count: number;
  last_activity_at: string | null;
};

const statusLabels: Record<AccountStatus, string> = {
  active: 'Active',
  setup_required: 'Password setup required',
  inactive: 'Inactive',
};

function formatDate(value?: string | null) {
  if (!value) return 'Never';
  return new Intl.DateTimeFormat(undefined, { dateStyle: 'medium' }).format(new Date(value));
}

function formatWhen(value?: string | null) {
  if (!value) return 'Never';
  const minutes = Math.max(0, Math.floor((Date.now() - new Date(value).getTime()) / 60_000));
  if (minutes < 1) return 'Just now';
  if (minutes < 60) return `${minutes} min ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours} hr ago`;
  const days = Math.floor(hours / 24);
  return `${days} day${days === 1 ? '' : 's'} ago`;
}

function eventLabel(eventType: string) {
  const labels: Record<string, string> = {
    login: 'Signed in',
    logout: 'Signed out',
    logout_all: 'Signed out everywhere',
    'password.change': 'Password changed',
    'password.setup': 'Password set',
    'session.revoke': 'Session revoked',
    'user.password_reset': 'Password reset issued',
    'user.sessions_revoked': 'All sessions revoked',
    'user.update': 'Account settings updated',
    'device.auth': 'Device authenticated',
    'device.ingest': 'Sensor data received',
    'device.actuator_state': 'Actuator state updated',
  };
  const fallback = eventType.replaceAll('.', ' ').replaceAll('_', ' ');
  return labels[eventType] || fallback.replace(/\b\w/g, (character) => character.toUpperCase());
}

function isRecent(value: string | null) {
  return value !== null && Date.now() - new Date(value).getTime() <= 30 * 86_400_000;
}

function DetailMeta({ label, value }: { label: string; value: string }) {
  return <div className="staff-detail-meta"><dt>{label}</dt><dd>{value}</dd></div>;
}

export function Staff() {
  const client = useQueryClient();
  const me = useMe();
  const query = useQuery({ queryKey: ['users'], queryFn: () => api<AdminUser[]>('/users') });
  const [creating, setCreating] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const [result, setResult] = useState<{ name: string; setupUrl: string; expiresAt: string; } | null>(null);
  const [deactivateTarget, setDeactivateTarget] = useState<AdminUser | null>(null);
  const [resetTarget, setResetTarget] = useState<AdminUser | null>(null);
  const [roleChange, setRoleChange] = useState<{ user: AdminUser; role: 'admin' | 'staff'; } | null>(null);
  const [selectedUserId, setSelectedUserId] = useState<number | null>(null);
  const [nameDraft, setNameDraft] = useState('');
  const [revokeOpen, setRevokeOpen] = useState(false);
  const [search, setSearch] = useState('');
  const [roleFilter, setRoleFilter] = useState<'all' | 'admin' | 'staff'>('all');
  const [statusFilter, setStatusFilter] = useState<'all' | AccountStatus>('all');
  const [activityFilter, setActivityFilter] = useState<ActivityFilter>('all');
  const [sessionVisibleCount, setSessionVisibleCount] = useState(5);
  const [activityVisibleCount, setActivityVisibleCount] = useState(5);

  const selectedFromList = query.data?.find((user) => user.id === selectedUserId);
  const detail = useQuery({
    queryKey: ['user', selectedUserId],
    queryFn: () => api<AdminUser>(`/users/${selectedUserId}`),
    enabled: selectedUserId !== null,
  });
  const sessions = useQuery({
    queryKey: ['user-sessions', selectedUserId],
    queryFn: () => api<AdminSession[]>(`/users/${selectedUserId}/sessions`),
    enabled: selectedUserId !== null,
  });
  const activity = useQuery({
    queryKey: ['user-activity', selectedUserId],
    queryFn: () => api<SecurityAuditEvent[]>(`/security/audit-events?user_id=${selectedUserId}&limit=12`),
    enabled: selectedUserId !== null,
  });

  const filteredUsers = useMemo(() => {
    const term = search.trim().toLowerCase();
    return (query.data ?? []).filter((user) => {
      const matchesSearch = !term || `${user.name} ${user.email}`.toLowerCase().includes(term);
      const matchesRole = roleFilter === 'all' || user.role === roleFilter;
      const matchesStatus = statusFilter === 'all' || user.account_status === statusFilter;
      const matchesActivity = activityFilter === 'all'
        || (activityFilter === 'never' && !user.last_activity_at)
        || (activityFilter === 'recent' && isRecent(user.last_activity_at))
        || (activityFilter === 'stale' && Boolean(user.last_activity_at) && !isRecent(user.last_activity_at));
      return matchesSearch && matchesRole && matchesStatus && matchesActivity;
    });
  }, [activityFilter, query.data, roleFilter, search, statusFilter]);

  const closeCreate = () => setCreating(false);

  const create = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    setBusy(true);
    setError('');
    const form = new FormData(event.currentTarget);
    try {
      const response = await api<{ user: User; setup_url: string; expires_at: string; }>('/users', {
        method: 'POST',
        body: JSON.stringify({ name: form.get('name'), email: form.get('email'), role: form.get('role') }),
      });
      setCreating(false);
      setResult({ name: response.user.name, setupUrl: response.setup_url, expiresAt: response.expires_at });
      await client.invalidateQueries({ queryKey: ['users'] });
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Unable to create staff member');
    } finally {
      setBusy(false);
    }
  };

  const update = async (id: number, body: object) => {
    setBusy(true);
    setError('');
    try {
      await api(`/users/${id}`, { method: 'PUT', body: JSON.stringify(body) });
      await client.invalidateQueries({ queryKey: ['users'] });
      if (selectedUserId === id) await detail.refetch();
      return true;
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Unable to update this account');
      return false;
    } finally {
      setBusy(false);
    }
  };

  const reset = async (user: AdminUser) => {
    setBusy(true);
    setError('');
    try {
      const response = await api<{ user: User; setup_url: string; expires_at: string; }>(
        `/users/${user.id}/reset-password`,
        { method: 'POST' },
      );
      setResult({ name: user.name, setupUrl: response.setup_url, expiresAt: response.expires_at });
      setResetTarget(null);
      await client.invalidateQueries({ queryKey: ['users'] });
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Unable to issue a setup link');
    } finally {
      setBusy(false);
    }
  };

  const revokeSessions = async () => {
    if (!selectedUserId) return;
    setBusy(true);
    setError('');
    try {
      const response = await api<{ revoked_count: number }>(`/users/${selectedUserId}/revoke-sessions`, { method: 'POST' });
      setNotice(`${response.revoked_count} session${response.revoked_count === 1 ? '' : 's'} revoked.`);
      setRevokeOpen(false);
      await Promise.all([
        client.invalidateQueries({ queryKey: ['users'] }),
        client.invalidateQueries({ queryKey: ['user', selectedUserId] }),
        client.invalidateQueries({ queryKey: ['user-sessions', selectedUserId] }),
        client.invalidateQueries({ queryKey: ['user-activity', selectedUserId] }),
      ]);
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Unable to revoke sessions');
    } finally {
      setBusy(false);
    }
  };

  const selectedUser = detail.data ?? selectedFromList;
  const openDetail = (id: number) => {
    setSelectedUserId(id);
    setNameDraft(query.data?.find((user) => user.id === id)?.name ?? '');
    setSessionVisibleCount(5);
    setActivityVisibleCount(5);
  };
  const visibleSessions = (sessions.data ?? []).slice(0, sessionVisibleCount);
  const activityRecords = (activity.data ?? []).filter((event) => event.event_type !== 'refresh');
  const routineActivityCount = (activity.data ?? []).filter((event) => event.event_type === 'refresh').length;
  const visibleActivity = activityRecords.slice(0, activityVisibleCount);
  const hasMoreSessions = (sessions.data?.length ?? 0) > sessionVisibleCount;
  const hasMoreActivity = activityRecords.length > activityVisibleCount;
  const saveName = async () => {
    if (selectedUserId === null || !nameDraft.trim()) return;
    if (await update(selectedUserId, { name: nameDraft.trim() })) setNotice('Account name updated.');
  };

  return (
    <section className="staff-page">
      <Link className="account-back-link" to="/admin/account">
        <ArrowLeft size={16} aria-hidden="true" /> Back to Account center
      </Link>
      <PageHeader
        eyebrow="Administration"
        title="Staff & roles"
        description="Manage account lifecycle, understand access, and investigate security context."
        actions={
          <button className="button button-primary" type="button" onClick={() => setCreating(true)}>
            <UserPlus size={17} /> Add staff
          </button>
        }
      />

      {(error || notice) && <Notice tone={error ? 'error' : 'success'}>{error || notice}</Notice>}

      <Panel title="Access lifecycle" description={`${filteredUsers.length} of ${query.data?.length ?? 0} team members`}>
        <div className="staff-filter-bar" aria-label="Filter staff accounts">
          <label className="staff-search-field">
            <Search size={16} aria-hidden="true" />
            <span className="sr-only">Search by name or email</span>
            <input value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Search name or email" />
          </label>
          <label className="compact-select"><span className="sr-only">Filter by role</span><select value={roleFilter} onChange={(event) => setRoleFilter(event.target.value as typeof roleFilter)}><option value="all">All roles</option><option value="admin">Administrators</option><option value="staff">Staff</option></select></label>
          <label className="compact-select"><span className="sr-only">Filter by account status</span><select value={statusFilter} onChange={(event) => setStatusFilter(event.target.value as typeof statusFilter)}><option value="all">All statuses</option><option value="active">Active</option><option value="setup_required">Password setup required</option><option value="inactive">Inactive</option></select></label>
          <label className="compact-select"><span className="sr-only">Filter by recent activity</span><select value={activityFilter} onChange={(event) => setActivityFilter(event.target.value as ActivityFilter)}><option value="all">Any activity</option><option value="recent">Active in 30 days</option><option value="stale">No activity in 30 days</option><option value="never">Never active</option></select></label>
          <span className="staff-filter-icon" aria-hidden="true"><ListFilter size={17} /></span>
        </div>

        {query.isLoading ? (
          <LoadingState label="Loading staff…" />
        ) : query.isError ? (
          <ErrorState message="Staff accounts could not be loaded." retry={() => query.refetch()} />
        ) : filteredUsers.length ? (
          <div className="data-table staff-table">
            <div className="data-head">
              <span>Staff member</span><span>Role</span><span>Status</span><span>Last activity</span><span>Sessions</span><span>Actions</span>
            </div>
            {filteredUsers.map((user) => (
              <div className="data-row" key={user.id}>
                <button className="staff-member-button" type="button" onClick={() => openDetail(user.id)}>
                  <span className="person-cell"><span className="avatar">{initials(user.name)}</span><span><strong>{user.name}</strong><small>{user.email}</small></span></span>
                </button>
                <label className="compact-select"><span className="sr-only">Role for {user.name}</span><select value={user.role} disabled={busy} onChange={(event) => setRoleChange({ user, role: event.target.value as 'admin' | 'staff' })}><option value="staff">Staff</option><option value="admin">Administrator</option></select></label>
                <LifecycleBadge status={user.account_status} />
                <span className="staff-activity-cell"><strong>{formatWhen(user.last_activity_at)}</strong><small>{formatDate(user.last_activity_at)}</small></span>
                <span className="staff-session-count"><Laptop size={15} aria-hidden="true" />{user.active_session_count}</span>
                <span className="row-actions row-actions-text">
                  <button className="button button-secondary button-small" type="button" disabled={busy} onClick={() => user.is_active ? setDeactivateTarget(user) : void update(user.id, { is_active: true })}>{user.is_active ? 'Deactivate' : 'Activate'}</button>
                  {user.is_active && <button className="button button-secondary button-small" type="button" disabled={busy} onClick={() => setResetTarget(user)}>{user.must_change_password ? 'Issue new setup link' : 'Reset password'}</button>}
                  <button className="button button-secondary button-small staff-view-account" type="button" onClick={() => openDetail(user.id)}>View account</button>
                </span>
              </div>
            ))}
          </div>
        ) : (
          <EmptyState title="No matching accounts" message="Adjust the search or lifecycle filters to see more team members." />
        )}
      </Panel>

      <Drawer open={creating} title="Add staff member" description="Create a staff account and assign its initial access role." onClose={closeCreate} footer={<div className="drawer-actions"><button className="button button-secondary" type="button" onClick={closeCreate}>Cancel</button><button className="button button-primary" type="submit" form="staff-form">{busy ? 'Creating…' : 'Create staff'}</button></div>}>
        <form id="staff-form" className="drawer-form" onSubmit={create}>
          {error && <Notice tone="error">{error}</Notice>}
          <div className="form-section">
            <label className="field"><span>Full name</span><input name="name" required /></label>
            <label className="field"><span>Email address</span><input name="email" type="email" required /></label>
            <label className="field"><span>Role</span><select name="role"><option value="staff">Staff</option><option value="admin">Administrator</option></select></label>
          </div>
        </form>
      </Drawer>

      <Drawer open={selectedUserId !== null} title={selectedUser?.name ?? 'Account details'} description={selectedUser?.email ?? 'Loading account details'} onClose={() => setSelectedUserId(null)}>
        {detail.isLoading ? <LoadingState label="Loading account details…" /> : detail.isError ? <ErrorState message="Account details could not be loaded." retry={() => detail.refetch()} /> : selectedUser ? (
          <div className="staff-detail-drawer">
            <section className="staff-detail-section"><h3><Users size={17} /> Overview</h3><label className="field"><span>Name</span><input value={nameDraft} onChange={(event) => setNameDraft(event.target.value)} maxLength={120} /></label><button className="button button-secondary button-small staff-save-name" type="button" disabled={busy || !nameDraft.trim() || nameDraft.trim() === selectedUser.name} onClick={() => void saveName()}>Save name</button><dl className="staff-detail-meta-grid"><DetailMeta label="Email" value={selectedUser.email} /><DetailMeta label="Status" value={statusLabels[selectedUser.account_status]} /><DetailMeta label="Role" value={selectedUser.role === 'admin' ? 'Administrator' : 'Staff'} /><DetailMeta label="Created" value={formatDate(selectedUser.created_at)} /><DetailMeta label="Last activity" value={formatDate(selectedUser.last_activity_at)} /></dl></section>
            <section className="staff-detail-section"><h3><ShieldCheck size={17} /> Access</h3><p className="staff-detail-copy">{selectedUser.role === 'admin' ? 'Administrator access includes all staff capabilities plus staff lifecycle management and security audit activity.' : 'Staff access includes operational reads, alert resolution, and species assignment. Account and security administration remain restricted.'}</p><span className="account-role-chip">{statusLabels[selectedUser.account_status]}</span></section>
            <section className="staff-detail-section"><h3><KeyRound size={17} /> Security</h3><div className="staff-detail-section-heading"><span><strong>{sessions.data?.length ?? selectedUser.active_session_count} active sessions</strong><small>Only device descriptions and session times are shown.</small></span><button className="button button-danger button-small" type="button" disabled={busy || selectedUser.id === me.data?.id || !sessions.data?.length} onClick={() => setRevokeOpen(true)}><LogOut size={15} /> Revoke all</button></div>{sessions.isLoading ? <LoadingState label="Loading sessions…" /> : sessions.isError ? <ErrorState message="Sessions could not be loaded." retry={() => sessions.refetch()} /> : sessions.data?.length ? <><div className="staff-session-list">{visibleSessions.map((session) => <div className="staff-session-item" key={session.id}><Laptop size={16} aria-hidden="true" /><span><strong>{session.user_agent || 'Unknown device'}</strong><small>Signed in {formatDate(session.created_at)} · Last active {formatWhen(session.last_seen_at)} · Expires {formatDate(session.expires_at)}</small></span></div>)}</div>{(hasMoreSessions || sessionVisibleCount > 5) && <button className="button button-ghost button-small staff-history-toggle" type="button" onClick={() => setSessionVisibleCount((count) => hasMoreSessions ? Math.min(count + 5, sessions.data?.length ?? count) : 5)}>{hasMoreSessions ? <><ChevronDown size={15} /> Load more sessions</> : <><ChevronUp size={15} /> Show fewer sessions</>}</button>}</> : <EmptyState title="No active sessions" message="This account has no sessions available to revoke." />}</section>
            <section className="staff-detail-section"><h3><Clock3 size={17} /> Activity</h3>{activity.isLoading ? <LoadingState label="Loading activity…" /> : activity.isError ? <ErrorState message="Account activity could not be loaded." retry={() => activity.refetch()} /> : activity.data?.length ? <>{routineActivityCount > 0 && <p className="staff-history-summary">{routineActivityCount} routine refresh{routineActivityCount === 1 ? '' : 'es'} grouped</p>}{activityRecords.length ? <div className="staff-activity-list">{visibleActivity.map((event) => <div className="staff-activity-item" key={event.id}><CheckCircle2 size={16} aria-hidden="true" /><span><strong>{eventLabel(event.event_type)}</strong><small>{formatDate(event.created_at)} · {event.outcome}</small></span></div>)}</div> : <EmptyState title="No account changes" message="Routine session refreshes are grouped above." />}{(hasMoreActivity || activityVisibleCount > 5) && <button className="button button-ghost button-small staff-history-toggle" type="button" onClick={() => setActivityVisibleCount((count) => hasMoreActivity ? Math.min(count + 5, activityRecords.length) : 5)}>{hasMoreActivity ? <><ChevronDown size={15} /> Load more activity</> : <><ChevronUp size={15} /> Show less activity</>}</button>}</> : <EmptyState title="No account activity" message="Security events for this account will appear here." />}</section>
          </div>
        ) : null}
      </Drawer>

      <ConfirmDialog open={Boolean(deactivateTarget)} title={`Deactivate ${deactivateTarget?.name ?? 'staff member'}?`} message="They will no longer be able to sign in until the account is reactivated. Existing access will stop immediately." confirmLabel="Deactivate account" busy={busy} onConfirm={async () => { if (!deactivateTarget) return; if (await update(deactivateTarget.id, { is_active: false })) setDeactivateTarget(null); }} onClose={() => !busy && setDeactivateTarget(null)} />
      <ConfirmDialog open={Boolean(resetTarget)} title={`${resetTarget?.must_change_password ? 'Issue a new setup link for' : 'Reset the password for'} ${resetTarget?.name ?? 'this account'}?`} message="Existing sessions will be invalidated and the account will need to complete the one-time password setup link." confirmLabel={resetTarget?.must_change_password ? 'Issue setup link' : 'Reset password'} busy={busy} onConfirm={() => resetTarget ? void reset(resetTarget) : undefined} onClose={() => !busy && setResetTarget(null)} />
      <ConfirmDialog open={revokeOpen} title="Revoke every session?" message="This account will be signed out from every active device and must sign in again." confirmLabel="Revoke all sessions" busy={busy} onConfirm={() => void revokeSessions()} onClose={() => !busy && setRevokeOpen(false)} />
      <ConfirmDialog open={Boolean(roleChange)} title={`Change ${roleChange?.user.name ?? 'account'} role?`} message={`This will change the account's access to ${roleChange?.role === 'admin' ? 'Administrator' : 'Staff'} and will apply to subsequent authorization checks.`} confirmLabel="Change role" busy={busy} onConfirm={async () => { if (!roleChange) return; if (await update(roleChange.user.id, { role: roleChange.role })) setRoleChange(null); }} onClose={() => !busy && setRoleChange(null)} />

      <Drawer open={Boolean(result)} title="One-time setup link" description="This link is shown once. Copy it and share it through a secure channel; it expires in 30 minutes." onClose={() => setResult(null)}>
        {result && <div className="temporary-password"><span><small>Staff member</small><strong>{result.name}</strong></span><code>{result.setupUrl}</code><small>Expires {formatDate(result.expiresAt)}</small><button className="button button-primary" type="button" onClick={() => navigator.clipboard.writeText(result.setupUrl)}><Clipboard size={17} /> Copy setup link</button></div>}
      </Drawer>
    </section>
  );
}

export default Staff;

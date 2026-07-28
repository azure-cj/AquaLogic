import { api, clearSession } from '@/shared/api/client';
import {
  ConfirmDialog,
  EmptyState,
  ErrorState,
  LoadingState,
  Notice,
  PageHeader,
  Panel,
} from '@/shared/components/admin-ui';
import { useMe } from '@/shared/hooks/useMe';
import { useInfiniteQuery, useQuery, useQueryClient } from '@tanstack/react-query';
import {
  AlertTriangle,
  ArrowLeft,
  CheckCircle2,
  ChevronRight,
  Clock3,
  History,
  KeyRound,
  Laptop,
  LogOut,
  Monitor,
  ShieldCheck,
  Smartphone,
} from 'lucide-react';
import { type FormEvent, useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import './security.css';

type Session = {
  id: string;
  created_at: string;
  last_seen_at?: string | null;
  expires_at: string;
  current: boolean;
  user_agent?: string | null;
};

type AuditEvent = {
  id: number;
  event_type: string;
  outcome: string;
  actor_user_id?: number | null;
  created_at: string;
};

const auditPageSize = 12;

function formatWhen(value?: string | null) {
  if (!value) return 'Just now';
  const date = new Date(value);
  const difference = Date.now() - date.getTime();
  const minutes = Math.max(0, Math.floor(difference / 60_000));
  if (minutes < 1) return 'Just now';
  if (minutes < 60) return `${minutes} min ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours} hr ago`;
  const days = Math.floor(hours / 24);
  return `${days} day${days === 1 ? '' : 's'} ago`;
}

function formatTimestamp(value: string) {
  return new Intl.DateTimeFormat(undefined, {
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(new Date(value));
}

function deviceDetails(userAgent?: string | null) {
  const source = userAgent || '';
  const browser = source.includes('Edg/')
    ? 'Microsoft Edge'
    : source.includes('Firefox/')
      ? 'Firefox'
      : source.includes('Chrome/')
        ? 'Chrome'
        : source.includes('Safari/')
          ? 'Safari'
          : 'Browser';
  const platform = source.includes('Windows')
    ? 'Windows'
    : source.includes('Mac OS')
      ? 'macOS'
      : source.includes('iPhone') || source.includes('Android')
        ? 'Mobile device'
        : 'Unknown device';
  const mobile = source.includes('iPhone') || source.includes('Android') || source.includes('Mobile');
  return { browser, platform, mobile };
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
    'user.update': 'Account settings updated',
    'refresh.replay': 'Session replay blocked',
  };
  return labels[eventType] || eventType.replaceAll('.', ' ').replaceAll('_', ' ');
}

function eventIcon(eventType: string) {
  if (eventType.includes('password')) return <KeyRound size={17} />;
  if (eventType.includes('session') || eventType.includes('logout')) return <LogOut size={17} />;
  if (eventType.includes('login')) return <ShieldCheck size={17} />;
  return <History size={17} />;
}

export default function SecurityPage() {
  const client = useQueryClient();
  const me = useMe();
  const sessions = useQuery({
    queryKey: ['auth-sessions'],
    queryFn: () => api<Session[]>('/auth/sessions'),
  });
  const audit = useInfiniteQuery({
    queryKey: ['security-audit-events'],
    initialPageParam: undefined as number | undefined,
    queryFn: ({ pageParam }) => api<AuditEvent[]>(
      `/security/audit-events?limit=${auditPageSize}${pageParam ? `&before_id=${pageParam}` : ''}`,
    ),
    getNextPageParam: (page) => (
      page.length === auditPageSize ? page[page.length - 1]?.id : undefined
    ),
    enabled: me.data?.role === 'admin',
  });
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const [sessionToRevoke, setSessionToRevoke] = useState<Session | null>(null);
  const [revoking, setRevoking] = useState(false);
  const [showSignOutForm, setShowSignOutForm] = useState(false);
  const [signingOut, setSigningOut] = useState(false);

  const auditEvents = useMemo(
    () => audit.data?.pages.flat() ?? [],
    [audit.data],
  );
  const routineRefreshes = auditEvents.filter((event) => event.event_type === 'refresh');
  const meaningfulAuditEvents = auditEvents.filter((event) => event.event_type !== 'refresh');

  const revoke = async () => {
    if (!sessionToRevoke) return;
    setError('');
    setRevoking(true);
    try {
      await api(`/auth/sessions/${sessionToRevoke.id}`, { method: 'DELETE' });
      await client.invalidateQueries({ queryKey: ['auth-sessions'] });
      setNotice('Device access revoked.');
      setSessionToRevoke(null);
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Unable to revoke this device');
    } finally {
      setRevoking(false);
    }
  };

  const logoutAll = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    setError('');
    setSigningOut(true);
    const form = new FormData(event.currentTarget);
    try {
      await api('/auth/logout-all', {
        method: 'POST',
        body: JSON.stringify({ current_password: form.get('password') }),
      });
      clearSession();
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Unable to sign out every device');
    } finally {
      setSigningOut(false);
    }
  };

  return (
    <section className="security-page">
      <Link className="account-back-link" to="/admin/account">
        <ArrowLeft size={16} aria-hidden="true" /> Back to Account center
      </Link>
      <PageHeader
        eyebrow="Your account"
        title="Security center"
        description="Review signed-in devices, remove access you do not recognize, and keep track of meaningful account activity."
      />

      {notice && <Notice>{notice}</Notice>}
      {error && <Notice tone="error">{error}</Notice>}

      <div className="security-layout">
        <Panel
          className="security-sessions-panel"
          title="Signed-in devices"
          description="Sessions expire after seven days. Revoke access from any device you do not recognize."
          action={
            sessions.data ? <span className="security-count">{sessions.data.length} active</span> : undefined
          }
        >
          {sessions.isLoading ? (
            <LoadingState label="Loading signed-in devices…" />
          ) : sessions.isError ? (
            <ErrorState message="Signed-in devices could not be loaded." retry={() => sessions.refetch()} />
          ) : sessions.data?.length ? (
            <div className="security-session-list">
              {sessions.data.map((session) => {
                const device = deviceDetails(session.user_agent);
                const DeviceIcon = device.mobile ? Smartphone : session.current ? Laptop : Monitor;
                return (
                  <article className="security-session" key={session.id}>
                    <span className="security-device-icon" aria-hidden="true">
                      <DeviceIcon size={20} />
                    </span>
                    <div className="security-session-content">
                      <div className="security-session-heading">
                        <div>
                          <strong>{session.current ? 'This device' : `${device.browser} on ${device.platform}`}</strong>
                          <span>{session.current ? `${device.browser} on ${device.platform}` : 'Signed-in device'}</span>
                        </div>
                        {session.current && <span className="security-current-badge"><CheckCircle2 size={14} />Current</span>}
                      </div>
                      <div className="security-session-meta">
                        <span><Clock3 size={14} />Active {formatWhen(session.last_seen_at)}</span>
                        <span>Expires {formatWhen(session.expires_at)}</span>
                      </div>
                      {session.user_agent && (
                        <details className="security-technical-details">
                          <summary>Technical details <ChevronRight size={14} /></summary>
                          <span>{session.user_agent}</span>
                        </details>
                      )}
                    </div>
                    {!session.current && (
                      <button
                        className="button button-secondary button-small"
                        type="button"
                        onClick={() => setSessionToRevoke(session)}
                        aria-label={`Revoke access for ${device.browser} on ${device.platform}`}
                      >
                        Revoke access
                      </button>
                    )}
                  </article>
                );
              })}
            </div>
          ) : (
            <EmptyState title="No active devices" message="Sign in again to create a new session." />
          )}
        </Panel>

        <aside className="security-side-column">
          <Panel
            className="security-danger-panel"
            title="Sign out everywhere"
            description="End every active session, including this one."
          >
            <div className="security-danger-content">
              <span className="security-danger-icon" aria-hidden="true"><AlertTriangle size={20} /></span>
              <p>Use this if you suspect your account was accessed from an unfamiliar device.</p>
              {!showSignOutForm ? (
                <button className="button button-danger" type="button" onClick={() => setShowSignOutForm(true)}>
                  Sign out everywhere
                </button>
              ) : (
                <form className="security-signout-form" onSubmit={logoutAll}>
                  <label className="field">
                    <span>Confirm with your current password</span>
                    <input
                      autoComplete="current-password"
                      name="password"
                      type="password"
                      minLength={1}
                      maxLength={128}
                      required
                      autoFocus
                    />
                  </label>
                  <div className="security-danger-actions">
                    <button className="button button-secondary" type="button" onClick={() => setShowSignOutForm(false)}>
                      Cancel
                    </button>
                    <button className="button button-danger" type="submit" disabled={signingOut}>
                      {signingOut ? 'Signing out…' : 'Confirm sign out'}
                    </button>
                  </div>
                </form>
              )}
            </div>
          </Panel>

          <div className="security-reassurance">
            <ShieldCheck size={18} aria-hidden="true" />
            <p>Access is protected with rotating sessions. A revoked device cannot obtain a new access token.</p>
          </div>
        </aside>
      </div>

      {me.data?.role === 'admin' && (
        <Panel
          className="security-audit-panel"
          title="Security activity"
          description="Account-changing events are shown first; routine token refreshes are grouped to keep this feed useful."
        >
          {audit.isLoading ? (
            <LoadingState label="Loading security activity…" />
          ) : audit.isError ? (
            <ErrorState message="Security activity could not be loaded." retry={() => audit.refetch()} />
          ) : (
            <div className="security-audit-list">
              {meaningfulAuditEvents.length ? meaningfulAuditEvents.map((event) => (
                <article className="security-event" key={event.id}>
                  <span className="security-event-icon" aria-hidden="true">{eventIcon(event.event_type)}</span>
                  <div>
                    <strong>{eventLabel(event.event_type)}</strong>
                    <time dateTime={event.created_at} title={formatTimestamp(event.created_at)}>{formatWhen(event.created_at)}</time>
                  </div>
                  <span className={`security-event-outcome security-event-outcome-${event.outcome}`}>
                    {event.outcome}
                  </span>
                </article>
              )) : (
                <EmptyState
                  title="No recent account changes"
                  message={routineRefreshes.length ? 'Routine session refreshes are being grouped below.' : 'Security-relevant activity will appear here.'}
                />
              )}
              {routineRefreshes.length > 0 && (
                <p className="security-routine-summary"><History size={15} />{routineRefreshes.length} routine refresh{routineRefreshes.length === 1 ? '' : 'es'} grouped</p>
              )}
              {audit.hasNextPage && (
                <button
                  className="button button-secondary security-load-more"
                  type="button"
                  onClick={() => void audit.fetchNextPage()}
                  disabled={audit.isFetchingNextPage}
                >
                  {audit.isFetchingNextPage ? 'Loading older activity…' : 'Load older activity'}
                </button>
              )}
            </div>
          )}
        </Panel>
      )}

      <ConfirmDialog
        open={sessionToRevoke !== null}
        title="Revoke device access?"
        message="This device will be signed out immediately and will need to sign in again."
        confirmLabel="Revoke access"
        busy={revoking}
        onConfirm={() => void revoke()}
        onClose={() => !revoking && setSessionToRevoke(null)}
      />
    </section>
  );
}

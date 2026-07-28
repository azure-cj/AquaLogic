import { api, clearSession } from '@/shared/api/client';
import { ErrorState, LoadingState, Notice, PageHeader, Panel } from '@/shared/components/admin-ui';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { FormEvent, useState } from 'react';
import { useMe } from '@/shared/hooks/useMe';

type Session = { id: string; created_at: string; last_seen_at?: string | null; expires_at: string; current: boolean; user_agent?: string | null; };
type AuditEvent = { id: number; event_type: string; outcome: string; actor_user_id?: number | null; created_at: string; };

export default function SecurityPage() {
  const client = useQueryClient();
  const me = useMe();
  const sessions = useQuery({ queryKey: ['auth-sessions'], queryFn: () => api<Session[]>('/auth/sessions') });
  const audit = useQuery({ queryKey: ['security-audit-events'], queryFn: () => api<AuditEvent[]>('/security/audit-events?limit=25'), enabled: me.data?.role === 'admin' });
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const revoke = async (id: string) => {
    setError('');
    try { await api(`/auth/sessions/${id}`, { method: 'DELETE' }); await client.invalidateQueries({ queryKey: ['auth-sessions'] }); setNotice('Session revoked.'); }
    catch (caught) { setError(caught instanceof Error ? caught.message : 'Unable to revoke the session'); }
  };
  const logoutAll = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault(); setError('');
    const form = new FormData(event.currentTarget);
    try { await api('/auth/logout-all', { method: 'POST', body: JSON.stringify({ current_password: form.get('password') }) }); clearSession(); }
    catch (caught) { setError(caught instanceof Error ? caught.message : 'Unable to sign out every device'); }
  };
  return <section><PageHeader eyebrow="Account security" title="Sessions" description="Review the browsers signed in to your account and remove access you no longer recognize." />{notice && <Notice>{notice}</Notice>}{error && <Notice tone="error">{error}</Notice>}<Panel title="Active sessions" description="Sessions expire after seven days.">{sessions.isLoading ? <LoadingState label="Loading sessionsâ€¦" /> : sessions.isError ? <ErrorState message="Sessions could not be loaded." retry={() => sessions.refetch()} /> : <div className="resource-list">{sessions.data?.map((session) => <article className="resource-row" key={session.id}><span className="resource-primary"><strong>{session.current ? 'This browser' : 'Signed-in browser'}</strong><small>{session.user_agent || 'Browser details unavailable'} · Last active {session.last_seen_at ? new Date(session.last_seen_at).toLocaleString() : 'just now'}</small></span>{!session.current && <div className="row-actions"><button className="button button-secondary button-small" type="button" onClick={() => void revoke(session.id)}>Revoke</button></div>}</article>)}</div>}</Panel><Panel title="Sign out everywhere" description="This revokes every active session, including this browser."><form className="drawer-form" onSubmit={logoutAll}><label className="field"><span>Current password</span><input name="password" type="password" minLength={1} maxLength={128} required /></label><button className="button button-danger" type="submit">Sign out every device</button></form></Panel>{me.data?.role === 'admin' && <Panel title="Security audit" description="Most recent security-relevant events.">{audit.isLoading ? <LoadingState label="Loading audit eventsâ€¦" /> : <div className="resource-list">{audit.data?.map((event) => <article className="resource-row" key={event.id}><span className="resource-primary"><strong>{event.event_type}</strong><small>{event.outcome} · {new Date(event.created_at).toLocaleString()}</small></span></article>)}</div>}</Panel>}</section>;
}

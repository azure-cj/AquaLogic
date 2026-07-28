import { api, User } from '@/shared/api/client';
import {
  ConfirmDialog,
  Drawer,
  ErrorState,
  LoadingState,
  Notice,
  PageHeader,
  Panel,
  StatusBadge
} from '@/shared/components/admin-ui';
import {
  initials
} from '@/shared/utils/formatting';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import {
  ArrowLeft,
  Clipboard,
  UserPlus
} from 'lucide-react';
import {
  FormEvent,
  useCallback,
  useState
} from 'react';
import { Link } from 'react-router-dom';
import './styles.css';

export function Staff() {
  const client = useQueryClient();
  const query = useQuery({ queryKey: ['users'], queryFn: () => api<User[]>('/users') });
  const [creating, setCreating] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [result, setResult] = useState<{ name: string; setupUrl: string; expiresAt: string; } | null>(null);
  const [deactivateTarget, setDeactivateTarget] = useState<User | null>(null);
  const closeCreate = useCallback(() => setCreating(false), []);
  const create = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    setBusy(true);
    setError('');
    const form = new FormData(event.currentTarget);
    try {
      const response = await api<{ user: User; setup_url: string; expires_at: string; }>('/users', {
        method: 'POST',
        body: JSON.stringify({
          name: form.get('name'),
          email: form.get('email'),
          role: form.get('role'),
        }),
      });
      setCreating(false);
      setResult({ name: response.user.name, setupUrl: response.setup_url, expiresAt: response.expires_at });
      client.invalidateQueries({ queryKey: ['users'] });
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Unable to create staff member');
    } finally {
      setBusy(false);
    }
  };
  const update = async (id: number, body: object) => {
    setBusy(true);
    try {
      await api(`/users/${id}`, { method: 'PUT', body: JSON.stringify(body) });
      client.invalidateQueries({ queryKey: ['users'] });
    } finally {
      setBusy(false);
    }
  };
  const reset = async (user: User) => {
    setBusy(true);
    try {
      const response = await api<{ user: User; setup_url: string; expires_at: string; }>(
        `/users/${user.id}/reset-password`,
        { method: 'POST' },
      );
      setResult({ name: user.name, setupUrl: response.setup_url, expiresAt: response.expires_at });
    } finally {
      setBusy(false);
    }
  };

  return (
    <section>
      <Link className="account-back-link" to="/admin/account">
        <ArrowLeft size={16} aria-hidden="true" /> Back to Account center
      </Link>
      <PageHeader
        eyebrow="Administration"
        title="Staff & roles"
        description="Manage staff access, roles, account state, and password resets."
        actions={
          <button className="button button-primary" type="button" onClick={() => setCreating(true)}>
            <UserPlus size={17} /> Add staff
          </button>
        }
      />
      <Panel title="Staff directory" description={`${query.data?.length ?? 0} team members`}>
        {query.isLoading ? (
          <LoadingState label="Loading staff…" />
        ) : query.isError ? (
          <ErrorState message="Staff accounts could not be loaded." retry={() => query.refetch()} />
        ) : (
          <div className="data-table staff-table">
            <div className="data-head">
              <span>Staff member</span>
              <span>Role</span>
              <span>Status</span>
              <span>Account actions</span>
            </div>
            {query.data?.map((user) => (
              <div className="data-row" key={user.id}>
                <span className="person-cell">
                  <span className="avatar">{initials(user.name)}</span>
                  <span>
                    <strong>{user.name}</strong>
                    <small>{user.email}</small>
                  </span>
                </span>
                <label className="compact-select">
                  <span className="sr-only">Role for {user.name}</span>
                  <select
                    value={user.role}
                    disabled={busy}
                    onChange={(event) => update(user.id, { role: event.target.value })}
                  >
                    <option value="staff">Staff</option>
                    <option value="admin">Administrator</option>
                  </select>
                </label>
                <StatusBadge value={user.is_active ? 'normal' : 'offline'} />
                <span className="row-actions row-actions-text">
                  <button
                    className="button button-secondary button-small"
                    type="button"
                    disabled={busy}
                    onClick={() =>
                      user.is_active
                        ? setDeactivateTarget(user)
                        : update(user.id, { is_active: true })
                    }
                  >
                    {user.is_active ? 'Deactivate' : 'Activate'}
                  </button>
                  <button
                    className="button button-secondary button-small"
                    type="button"
                    disabled={busy}
                    onClick={() => reset(user)}
                  >
                    Reset password
                  </button>
                </span>
              </div>
            ))}
          </div>
        )}
      </Panel>
      <Drawer
        open={creating}
        title="Add staff member"
        description="Create a staff account and assign its initial access role."
        onClose={closeCreate}
        footer={
          <div className="drawer-actions">
            <button className="button button-secondary" type="button" onClick={closeCreate}>
              Cancel
            </button>
            <button className="button button-primary" type="submit" form="staff-form">
              {busy ? 'Creating…' : 'Create staff'}
            </button>
          </div>
        }
      >
        <form id="staff-form" className="drawer-form" onSubmit={create}>
          {error && <Notice tone="error">{error}</Notice>}
          <div className="form-section">
            <label className="field">
              <span>Full name</span>
              <input name="name" required />
            </label>
            <label className="field">
              <span>Email address</span>
              <input name="email" type="email" required />
            </label>
            <label className="field">
              <span>Role</span>
              <select name="role">
                <option value="staff">Staff</option>
                <option value="admin">Administrator</option>
              </select>
            </label>
          </div>
        </form>
      </Drawer>
      <ConfirmDialog
        open={Boolean(deactivateTarget)}
        title={`Deactivate ${deactivateTarget?.name ?? 'staff member'}?`}
        message="They will no longer be able to sign in until the account is reactivated."
        confirmLabel="Deactivate account"
        busy={busy}
        onConfirm={async () => {
          if (!deactivateTarget) return;
          await update(deactivateTarget.id, { is_active: false });
          setDeactivateTarget(null);
        }}
        onClose={() => setDeactivateTarget(null)}
      />
      <Drawer
        open={Boolean(result)}
        title="One-time setup link"
        description="This link is shown once. Copy it and share it through a secure channel; it expires in 30 minutes."
        onClose={() => setResult(null)}
      >
        {result && (
          <div className="temporary-password">
            <span>
              <small>Staff member</small>
              <strong>{result.name}</strong>
            </span>
            <code>{result.setupUrl}</code>
            <button
              className="button button-primary"
              type="button"
              onClick={() => navigator.clipboard.writeText(result.setupUrl)}
            >
              <Clipboard size={17} /> Copy setup link
            </button>
          </div>
        )}
      </Drawer>
    </section>
  );
}

export default Staff;

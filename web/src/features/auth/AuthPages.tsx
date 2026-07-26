import { api } from '@/shared/api/client';
import {
  Notice
} from '@/shared/components/admin-ui';
import { Brand } from '@/shared/components/Brand';
import {
  Eye,
  EyeOff,
  KeyRound,
  ShieldCheck
} from 'lucide-react';
import {
  FormEvent,
  ReactNode,
  useState
} from 'react';
import {
  useNavigate
} from 'react-router-dom';
import './styles.css';

function PasswordInput({ name, label, minLength }: { name: string; label: string; minLength?: number; }) {
  const [visible, setVisible] = useState(false);
  return (
    <label className="field">
      <span>{label}</span>
      <span className="password-field">
        <input
          required
          minLength={minLength}
          name={name}
          type={visible ? 'text' : 'password'}
        />
        <button
          className="icon-button"
          type="button"
          onClick={() => setVisible((value) => !value)}
          aria-label={visible ? 'Hide password' : 'Show password'}
        >
          {visible ? <EyeOff size={18} /> : <Eye size={18} />}
        </button>
      </span>
    </label>
  );
}

function AuthFrame({ children, title, message }: { children: ReactNode; title: string; message: string; }) {
  return (
    <main className="auth-layout">
      <section className="auth-story">
        <Brand />
        <div>
          <p className="eyebrow">Water intelligence</p>
          <h1>Every tank. One clear operational view.</h1>
          <p>
            Monitor water health, respond to alerts, and keep every aquatic environment
            performing at its best.
          </p>
        </div>
        <p className="auth-trust">
          <ShieldCheck size={18} aria-hidden="true" />
          Protected staff access
        </p>
      </section>
      <section className="auth-panel">
        <div className="auth-card">
          <span className="auth-icon" aria-hidden="true">
            <KeyRound size={22} />
          </span>
          <p className="eyebrow">AquaLogic operations</p>
          <h2>{title}</h2>
          <p className="auth-message">{message}</p>
          {children}
        </div>
      </section>
    </main>
  );
}

export function Login() {
  const nav = useNavigate();
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const submit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    setBusy(true);
    setError('');
    const form = new FormData(event.currentTarget);
    try {
      const response = await api<{ access_token: string; must_change_password: boolean; }>(
        '/auth/login',
        {
          method: 'POST',
          body: JSON.stringify({ email: form.get('email'), password: form.get('password') }),
        },
      );
      sessionStorage.setItem('aqualogic_token', response.access_token);
      nav(response.must_change_password ? '/admin/change-password' : '/admin/fleet');
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Unable to sign in');
    } finally {
      setBusy(false);
    }
  };
  return (
    <AuthFrame title="Welcome back" message="Sign in with your staff account to continue.">
      <form className="auth-form" onSubmit={submit}>
        {error && <Notice tone="error">{error}</Notice>}
        <label className="field">
          <span>Email address</span>
          <input required type="email" name="email" autoComplete="email" />
        </label>
        <PasswordInput name="password" label="Password" />
        <button className="button button-primary button-wide" disabled={busy}>
          {busy ? 'Signing in…' : 'Sign in'}
        </button>
      </form>
    </AuthFrame>
  );
}

export function ChangePassword() {
  const nav = useNavigate();
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const submit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    setBusy(true);
    setError('');
    const form = new FormData(event.currentTarget);
    try {
      await api('/auth/change-password', {
        method: 'POST',
        body: JSON.stringify({
          current_password: form.get('current'),
          new_password: form.get('new'),
        }),
      });
      nav('/admin/fleet');
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Unable to change password');
    } finally {
      setBusy(false);
    }
  };
  return (
    <AuthFrame
      title="Secure your account"
      message="Replace your temporary password before entering the command center."
    >
      <form className="auth-form" onSubmit={submit}>
        {error && <Notice tone="error">{error}</Notice>}
        <PasswordInput name="current" label="Current password" />
        <PasswordInput name="new" label="New password (12+ characters)" minLength={12} />
        <button className="button button-primary button-wide" disabled={busy}>
          {busy ? 'Updating…' : 'Continue securely'}
        </button>
      </form>
    </AuthFrame>
  );
}

export default Login;

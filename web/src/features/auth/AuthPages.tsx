import { api, AuthToken, setAccessToken } from '@/shared/api/client';
import { Notice } from '@/shared/components/admin-ui';
import { Brand } from '@/shared/components/Brand';
import { ThemeControl } from '@/shared/components/ThemeControl';
import { Eye, EyeOff, KeyRound, ShieldCheck } from 'lucide-react';
import { FormEvent, ReactNode, useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import './styles.css';

function PasswordInput({ name, label, minLength }: { name: string; label: string; minLength?: number; }) {
  const [visible, setVisible] = useState(false);
  return <label className="field"><span>{label}</span><span className="password-field"><input required minLength={minLength} maxLength={128} name={name} type={visible ? 'text' : 'password'} /><button className="icon-button" type="button" onClick={() => setVisible((value) => !value)} aria-label={visible ? 'Hide password' : 'Show password'}>{visible ? <EyeOff size={18} /> : <Eye size={18} />}</button></span></label>;
}

function AuthFrame({ children, title, message }: { children: ReactNode; title: string; message: string; }) {
  return <main className="auth-layout"><section className="auth-story"><Brand /><div><p className="eyebrow">Water intelligence</p><h1>Every tank. One clear operational view.</h1><p>Monitor water health, respond to alerts, and keep every aquatic environment performing at its best.</p></div><p className="auth-trust"><ShieldCheck size={18} aria-hidden="true" />Protected staff access</p></section><section className="auth-panel"><div className="auth-card"><div className="auth-card-topbar"><span className="auth-icon" aria-hidden="true"><KeyRound size={22} /></span><ThemeControl /></div><p className="eyebrow">AquaLogic operations</p><h2>{title}</h2><p className="auth-message">{message}</p>{children}</div></section></main>;
}

export function Login() {
  const nav = useNavigate();
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const submit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault(); setBusy(true); setError('');
    const form = new FormData(event.currentTarget);
    try {
      const response = await api<AuthToken>('/auth/login', { method: 'POST', body: JSON.stringify({ email: form.get('email'), password: form.get('password') }) });
      setAccessToken(response.access_token);
      nav(response.must_change_password ? '/admin/change-password' : '/admin/fleet');
    } catch (caught) { setError(caught instanceof Error ? caught.message : 'Unable to sign in'); }
    finally { setBusy(false); }
  };
  return <AuthFrame title="Welcome back" message="Sign in with your staff account to continue."><form className="auth-form" onSubmit={submit}>{error && <Notice tone="error">{error}</Notice>}<label className="field"><span>Email address</span><input required type="email" name="email" autoComplete="email" maxLength={255} /></label><PasswordInput name="password" label="Password" /><button className="button button-primary button-wide" disabled={busy}>{busy ? 'Signing in…' : 'Sign in'}</button></form></AuthFrame>;
}

export function ChangePassword() {
  const nav = useNavigate();
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const submit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault(); setBusy(true); setError('');
    const form = new FormData(event.currentTarget);
    try {
      const response = await api<AuthToken>('/auth/change-password', { method: 'POST', body: JSON.stringify({ current_password: form.get('current'), new_password: form.get('new') }) });
      setAccessToken(response.access_token); nav('/admin/fleet');
    } catch (caught) { setError(caught instanceof Error ? caught.message : 'Unable to change password'); }
    finally { setBusy(false); }
  };
  return <AuthFrame title="Secure your account" message="Replace your temporary password before entering the command center."><form className="auth-form" onSubmit={submit}>{error && <Notice tone="error">{error}</Notice>}<PasswordInput name="current" label="Current password" /><PasswordInput name="new" label="New password (12+ characters)" minLength={12} /><button className="button button-primary button-wide" disabled={busy}>{busy ? 'Updating…' : 'Continue securely'}</button></form></AuthFrame>;
}

export function SetupPassword() {
  const nav = useNavigate();
  // Capture the fragment during the initial render. React StrictMode runs
  // effects twice in development; reading the hash from the effect after the
  // first run has already removed it can otherwise erase a valid token.
  const [setupToken] = useState(() => new URLSearchParams(window.location.hash.slice(1)).get('token') || '');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  useEffect(() => {
    if (window.location.hash) {
      window.history.replaceState(null, '', `${window.location.pathname}${window.location.search}`);
    }
  }, []);
  const submit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (!setupToken) { setError('This setup link is invalid or expired. Ask an administrator for a new link.'); return; }
    setBusy(true); setError('');
    const form = new FormData(event.currentTarget);
    try {
      const response = await api<AuthToken>('/auth/setup-password', { method: 'POST', body: JSON.stringify({ token: setupToken, password: form.get('password') }) });
      setAccessToken(response.access_token); nav('/admin/fleet');
    } catch (caught) { setError(caught instanceof Error ? caught.message : 'Unable to set your password'); }
    finally { setBusy(false); }
  };
  return <AuthFrame title="Set your password" message="Choose a password with 12 to 128 characters to activate your account."><form className="auth-form" onSubmit={submit}>{error && <Notice tone="error">{error}</Notice>}<PasswordInput name="password" label="New password (12+ characters)" minLength={12} /><button className="button button-primary button-wide" disabled={busy}>{busy ? 'Saving…' : 'Activate account'}</button></form></AuthFrame>;
}

export default Login;

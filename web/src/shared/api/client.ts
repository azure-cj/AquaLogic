export type Reading = {
  id: number;
  device_id?: string | null;
  tank_id: number;
  timestamp: string;
  received_at?: string;
  temperature: number;
  ph: number;
  turbidity: number;
  dissolved_oxygen: number | null;
  tds: number;
  ammonia: number | null;
};

export type User = {
  id: number;
  name: string;
  email: string;
  role: 'admin' | 'staff';
  is_active: boolean;
  must_change_password: boolean;
  created_at?: string;
  account_status?: 'active' | 'setup_required' | 'inactive';
  password_changed_at?: string | null;
  active_session_count?: number;
  last_activity_at?: string | null;
};

export type AdminSession = {
  id: string;
  created_at: string;
  last_seen_at?: string | null;
  expires_at: string;
  user_agent?: string | null;
};

export type SecurityAuditEvent = {
  id: number;
  event_type: string;
  outcome: string;
  request_id?: string | null;
  actor_user_id?: number | null;
  target_type?: string | null;
  target_id?: string | null;
  created_at: string;
};

export type AuthToken = {
  access_token: string;
  expires_at: string;
  user: User;
  must_change_password: boolean;
};

const base = import.meta.env.VITE_API_BASE_URL || '/api';
const REQUEST_TIMEOUT_MS = 10_000;
let accessToken: string | null = null;
let refreshInFlight: Promise<boolean> | null = null;
const authChannel = typeof BroadcastChannel === 'undefined' ? null : new BroadcastChannel('aqualogic-auth');

export const token = () => accessToken;

export function setAccessToken(value: string | null) {
  accessToken = value;
}

function notifyUnauthorized(broadcast: boolean) {
  accessToken = null;
  window.dispatchEvent(new Event('aqualogic:unauthorized'));
  window.dispatchEvent(new Event('aqualogic:session-cleared'));
  if (broadcast) authChannel?.postMessage({ type: 'logout' });
}

export function clearSession({ broadcast = true }: { broadcast?: boolean; } = {}) {
  notifyUnauthorized(broadcast);
}

authChannel?.addEventListener('message', (event: MessageEvent<{ type?: string; }>) => {
  if (event.data?.type === 'logout') notifyUnauthorized(false);
});

export function apiErrorMessage(payload: unknown, status: number) {
  if (payload && typeof payload === 'object' && 'detail' in payload) {
    const detail = (payload as { detail: unknown; }).detail;
    if (typeof detail === 'string') return detail;
    if (Array.isArray(detail)) {
      const messages = detail
        .map((item) => item && typeof item === 'object' && 'msg' in item ? String((item as { msg: unknown; }).msg) : '')
        .filter(Boolean);
      if (messages.length) return messages.join('. ');
    }
  }
  return `Request failed (${status})`;
}

export class ApiError extends Error {
  constructor(message: string, public readonly status: number) {
    super(message);
    this.name = 'ApiError';
  }
}

async function request(path: string, init: RequestInit = {}, includeToken = true): Promise<Response> {
  const headers = new Headers(init.headers);
  if (!(typeof FormData !== 'undefined' && init.body instanceof FormData)) {
    headers.set('Content-Type', 'application/json');
  }
  if (includeToken && accessToken) headers.set('Authorization', `Bearer ${accessToken}`);
  const controller = new AbortController();
  const timeout = window.setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
  try {
    return await fetch(`${base}${path}`, {
      ...init,
      credentials: 'same-origin',
      headers,
      signal: init.signal ?? controller.signal,
    });
  } catch (caught) {
    if (caught instanceof DOMException && caught.name === 'AbortError') {
      throw new ApiError('The server did not respond in time. Check that the AquaLogic API is running.', 408);
    }
    throw caught;
  } finally {
    window.clearTimeout(timeout);
  }
}

export async function refreshAccessToken(): Promise<boolean> {
  if (!refreshInFlight) {
    refreshInFlight = request('/auth/refresh', { method: 'POST' }, false)
      .then(async (response) => {
        if (!response.ok) return false;
        const payload = await response.json() as AuthToken;
        accessToken = payload.access_token;
        return true;
      })
      .catch(() => false)
      .finally(() => { refreshInFlight = null; });
  }
  return refreshInFlight;
}

function canRefresh(path: string) {
  return !['/auth/login', '/auth/setup-password', '/auth/refresh'].includes(path)
    && (Boolean(accessToken) || path === '/auth/me');
}

export async function api<T>(path: string, init: RequestInit = {}): Promise<T> {
  let response = await request(path, init);
  if (response.status === 401 && canRefresh(path) && await refreshAccessToken()) {
    response = await request(path, init);
  }
  if (response.status === 401) clearSession();
  if (!response.ok) {
    const payload: unknown = await response.json().catch(() => ({}));
    throw new ApiError(apiErrorMessage(payload, response.status), response.status);
  }
  return response.status === 204 ? (undefined as T) : response.json();
}

export const statusText = (status: string) =>
  ({
    normal: 'Normal — readings are within configured limits',
    warning: 'Warning — a reading needs attention',
    critical: 'Critical — immediate attention required',
    offline: 'Offline — no recent sensor report',
  })[status] || status;

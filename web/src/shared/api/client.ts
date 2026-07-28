export type Reading = {
  id: number;
  tank_id: number;
  timestamp: string;
  temperature: number;
  ph: number;
  turbidity: number;
  dissolved_oxygen: number;
  tds: number;
  ammonia: number;
};

export type User = {
  id: number;
  name: string;
  email: string;
  role: 'admin' | 'staff';
  is_active: boolean;
  must_change_password: boolean;
};

export type AuthToken = {
  access_token: string;
  expires_at: string;
  user: User;
  must_change_password: boolean;
};

const base = import.meta.env.VITE_API_BASE_URL || '/api';
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
  return fetch(`${base}${path}`, {
    ...init,
    credentials: 'same-origin',
    headers: {
      'Content-Type': 'application/json',
      ...(includeToken && accessToken ? { Authorization: `Bearer ${accessToken}` } : {}),
      ...(init.headers || {}),
    },
  });
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
    normal: 'Normal â€” readings are within configured limits',
    warning: 'Warning â€” a reading needs attention',
    critical: 'Critical â€” immediate attention required',
    offline: 'Offline â€” no recent sensor report',
  })[status] || status;

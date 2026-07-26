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

const base = import.meta.env.VITE_API_BASE_URL || '/api';

export const token = () => sessionStorage.getItem('aqualogic_token');
export const clearSession = () => sessionStorage.removeItem('aqualogic_token');

export function apiErrorMessage(payload: unknown, status: number) {
  if (payload && typeof payload === 'object' && 'detail' in payload) {
    const detail = (payload as { detail: unknown; }).detail;
    if (typeof detail === 'string') return detail;
    if (Array.isArray(detail)) {
      const messages = detail
        .map((item) =>
          item && typeof item === 'object' && 'msg' in item
            ? String((item as { msg: unknown; }).msg)
            : '',
        )
        .filter(Boolean);
      if (messages.length) return messages.join('. ');
    }
  }
  return `Request failed (${status})`;
}

export async function api<T>(path: string, init: RequestInit = {}): Promise<T> {
  const response = await fetch(`${base}${path}`, {
    ...init,
    headers: {
      'Content-Type': 'application/json',
      ...(token() ? { Authorization: `Bearer ${token()}` } : {}),
      ...(init.headers || {}),
    },
  });
  if (response.status === 401) {
    clearSession();
    window.dispatchEvent(new Event('aqualogic:unauthorized'));
  }
  if (!response.ok) {
    const payload: unknown = await response.json().catch(() => ({}));
    throw new Error(apiErrorMessage(payload, response.status));
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

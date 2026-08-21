import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { fireEvent, render, screen, within } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { afterEach, describe, expect, it, vi } from 'vitest';

import Staff from './StaffPage';

const apiMock = vi.fn();

vi.mock('@/shared/api/client', () => ({
  api: (...args: unknown[]) => apiMock(...args),
  statusText: (value: string) => value,
}));

vi.mock('@/shared/hooks/useMe', () => ({
  useMe: () => ({ data: { id: 1, role: 'admin', name: 'Administrator' } }),
}));

const users = [
  {
    id: 1,
    name: 'Administrator',
    email: 'admin@example.com',
    role: 'admin',
    is_active: true,
    must_change_password: false,
    created_at: '2026-07-01T00:00:00Z',
    account_status: 'active',
    password_changed_at: '2026-07-01T00:00:00Z',
    active_session_count: 1,
    last_activity_at: '2026-08-21T00:00:00Z',
  },
  {
    id: 2,
    name: 'Pending Staff',
    email: 'pending@example.com',
    role: 'staff',
    is_active: true,
    must_change_password: true,
    created_at: '2026-08-01T00:00:00Z',
    account_status: 'setup_required',
    password_changed_at: null,
    active_session_count: 0,
    last_activity_at: null,
  },
];

afterEach(() => vi.clearAllMocks());

function renderPage({ history = false }: { history?: boolean } = {}) {
  apiMock.mockImplementation((path: string) => {
    if (path === '/users') return Promise.resolve(users);
    if (path === '/users/2') return Promise.resolve(users[1]);
    if (path === '/users/2/sessions') return Promise.resolve(history
      ? Array.from({ length: 7 }, (_, index) => ({
        id: `session-${index}`,
        created_at: '2026-08-20T00:00:00Z',
        last_seen_at: '2026-08-21T00:00:00Z',
        expires_at: '2026-08-27T00:00:00Z',
        user_agent: `Chrome on Windows ${index}`,
      }))
      : [{
        id: 'session-2',
        created_at: '2026-08-20T00:00:00Z',
        last_seen_at: '2026-08-21T00:00:00Z',
        expires_at: '2026-08-27T00:00:00Z',
        user_agent: 'Chrome on Windows',
      }]);
    if (path.startsWith('/security/audit-events')) return Promise.resolve(history
      ? Array.from({ length: 7 }, (_, index) => ({ id: index + 1, event_type: index === 0 ? 'user.password_reset' : 'user.update', outcome: 'success', created_at: '2026-08-21T00:00:00Z' }))
      : [{ id: 5, event_type: 'user.password_reset', outcome: 'success', created_at: '2026-08-21T00:00:00Z' }]);
    return Promise.resolve({});
  });
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <MemoryRouter><Staff /></MemoryRouter>
    </QueryClientProvider>,
  );
}

describe('StaffPage', () => {
  it('shows lifecycle status, activity metadata, and filters', async () => {
    renderPage();

    expect(await screen.findByText('Pending Staff')).toBeInTheDocument();
    expect(screen.getByLabelText('Password setup required')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Issue new setup link' })).toBeInTheDocument();
    fireEvent.change(screen.getByPlaceholderText('Search name or email'), { target: { value: 'pending@' } });
    expect(screen.getByText('Pending Staff')).toBeInTheDocument();
    expect(screen.getAllByRole('button', { name: 'View account' })).toHaveLength(1);
  });

  it('loads the detail drawer and requires confirmation for reset actions', async () => {
    renderPage();

    expect(await screen.findByText('Pending Staff')).toBeInTheDocument();
    fireEvent.click(screen.getAllByRole('button', { name: 'View account' })[1]);
    expect(await screen.findByRole('heading', { name: 'Security' })).toBeInTheDocument();
    expect(await screen.findByText('Chrome on Windows')).toBeInTheDocument();
    expect(await screen.findByText('Password reset issued')).toBeInTheDocument();

    fireEvent.click(screen.getByRole('button', { name: 'Issue new setup link' }));
    const confirmation = screen.getByRole('alertdialog');
    expect(confirmation).toHaveTextContent('Issue a new setup link for Pending Staff?');
    expect(apiMock.mock.calls.some(([path]) => path === '/users/2/reset-password')).toBe(false);
    fireEvent.click(within(confirmation).getByRole('button', { name: 'Cancel' }));
  });

  it('progressively reveals longer session and activity histories', async () => {
    renderPage({ history: true });

    expect(await screen.findByText('Pending Staff')).toBeInTheDocument();
    fireEvent.click(screen.getAllByRole('button', { name: 'View account' })[1]);

    expect(await screen.findByRole('button', { name: 'Load more sessions' })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Load more activity' })).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Load more sessions' }));
    fireEvent.click(screen.getByRole('button', { name: 'Load more activity' }));
    expect(screen.getByRole('button', { name: 'Show fewer sessions' })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Show less activity' })).toBeInTheDocument();
  });
});

import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router-dom';
import { afterEach, describe, expect, it, vi } from 'vitest';
import SecurityPage from './SecurityPage';

const apiMock = vi.fn();
const clearSessionMock = vi.fn();

vi.mock('@/shared/api/client', () => ({
  api: (...args: unknown[]) => apiMock(...args),
  clearSession: () => clearSessionMock(),
}));

vi.mock('@/shared/hooks/useMe', () => ({
  useMe: () => ({ data: { role: 'admin' } }),
}));

afterEach(() => vi.clearAllMocks());

function renderPage() {
  const client = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  });
  return render(
    <QueryClientProvider client={client}>
      <MemoryRouter>
        <SecurityPage />
      </MemoryRouter>
    </QueryClientProvider>,
  );
}

describe('SecurityPage', () => {
  it('provides a path back to the Account center', () => {
    renderPage();

    expect(screen.getByRole('link', { name: 'Back to Account center' })).toHaveAttribute(
      'href',
      '/admin/account',
    );
  });

  it('presents readable device cards and groups routine refresh activity', async () => {
    apiMock.mockImplementation((path: string) => {
      if (path === '/auth/sessions') {
        return Promise.resolve([
          {
            id: 'current',
            current: true,
            created_at: '2026-07-29T01:00:00Z',
            last_seen_at: '2026-07-29T01:10:00Z',
            expires_at: '2026-08-05T01:00:00Z',
            user_agent: 'Mozilla/5.0 (Windows NT 10.0) Chrome/150.0',
          },
          {
            id: 'other',
            current: false,
            created_at: '2026-07-28T01:00:00Z',
            last_seen_at: '2026-07-28T01:10:00Z',
            expires_at: '2026-08-04T01:00:00Z',
            user_agent: 'Mozilla/5.0 (Mac OS X) Safari/537.36',
          },
        ]);
      }
      if (path === '/users') {
        return Promise.resolve([{ id: 1, name: 'Admin', email: 'admin@example.com' }]);
      }
      return Promise.resolve([
        { id: 4, event_type: 'password.change', outcome: 'success', created_at: '2026-07-29T01:10:00Z' },
        { id: 3, event_type: 'refresh', outcome: 'success', created_at: '2026-07-29T01:09:00Z' },
        { id: 2, event_type: 'refresh', outcome: 'success', created_at: '2026-07-29T01:08:00Z' },
      ]);
    });

    renderPage();

    expect(await screen.findByText('This device')).toBeInTheDocument();
    expect(screen.getByText('Chrome on Windows')).toBeInTheDocument();
    expect(screen.getAllByText('Technical details')).toHaveLength(2);
    expect((await screen.findAllByText('Password changed')).length).toBeGreaterThan(1);
    expect(screen.getByText('2 routine refreshes grouped')).toBeInTheDocument();
    expect(screen.queryByText('refresh', { exact: true })).not.toBeInTheDocument();
  });

  it('groups repetitive bridge telemetry and keeps future expiry readable', async () => {
    const futureExpiry = new Date(Date.now() + 3 * 86_400_000).toISOString();
    apiMock.mockImplementation((path: string) => {
      if (path === '/auth/sessions') return Promise.resolve([{
        id: 'future',
        current: false,
        created_at: new Date(Date.now() - 86_400_000).toISOString(),
        last_seen_at: new Date(Date.now() - 60_000).toISOString(),
        expires_at: futureExpiry,
        user_agent: 'Mozilla/5.0 (Windows NT 10.0) Chrome/150.0',
      }]);
      if (path === '/users') return Promise.resolve([]);
      return Promise.resolve([
        { id: 8, event_type: 'device.ingest', outcome: 'success', created_at: new Date().toISOString() },
        { id: 7, event_type: 'device.actuator_state', outcome: 'success', created_at: new Date().toISOString() },
      ]);
    });

    renderPage();

    expect(await screen.findByText(/in \d+ days/)).toBeInTheDocument();
    expect(screen.getByText('2 bridge updates grouped')).toBeInTheDocument();
    expect(screen.getByText('No recent account changes')).toBeInTheDocument();
  });

  it('requires an explicit confirmation before revoking a device or signing out everywhere', async () => {
    apiMock.mockImplementation((path: string) => {
      if (path === '/auth/sessions') {
        return Promise.resolve([
          {
            id: 'other',
            current: false,
            created_at: '2026-07-28T01:00:00Z',
            last_seen_at: '2026-07-28T01:10:00Z',
            expires_at: '2026-08-04T01:00:00Z',
            user_agent: 'Mozilla/5.0 (Windows NT 10.0) Chrome/150.0',
          },
        ]);
      }
      if (path === '/users') return Promise.resolve([{ id: 1, name: 'Admin', email: 'admin@example.com' }]);
      return Promise.resolve([]);
    });

    renderPage();

    const revokeButton = await screen.findByRole('button', { name: 'Revoke access for Chrome on Windows' });
    fireEvent.click(revokeButton);
    const confirmation = screen.getByRole('alertdialog');
    expect(confirmation).toHaveTextContent('Revoke device access?');
    expect(apiMock).toHaveBeenCalled();

    fireEvent.click(within(confirmation).getByRole('button', { name: 'Cancel' }));
    fireEvent.click(screen.getByRole('button', { name: 'Sign out everywhere' }));
    expect(screen.getByLabelText('Confirm with your current password')).toBeInTheDocument();
  });

  it('applies administrator audit filters to the request', async () => {
    const auditPaths: string[] = [];
    apiMock.mockImplementation((path: string) => {
      if (path === '/auth/sessions') return Promise.resolve([]);
      if (path === '/users') return Promise.resolve([{ id: 7, name: 'Operator', email: 'operator@example.com' }]);
      if (path.startsWith('/security/audit-events')) {
        auditPaths.push(path);
        return Promise.resolve([{ id: 9, event_type: 'user.update', outcome: 'success', created_at: '2026-08-21T01:00:00Z' }]);
      }
      return Promise.resolve([]);
    });

    renderPage();
    expect(await screen.findByText('Account settings updated')).toBeInTheDocument();
    await screen.findByRole('option', { name: /Operator/ });
    const user = userEvent.setup();
    await user.selectOptions(screen.getByLabelText('Account'), '7');
    await user.selectOptions(screen.getByLabelText('Event'), 'user.update');
    await user.selectOptions(screen.getByLabelText('Outcome'), 'success');

    await waitFor(() => expect(auditPaths.some((path) => path.includes('user_id=7'))).toBe(true));
    expect(auditPaths.some((path) => path.includes('event_type=user.update') && path.includes('outcome=success'))).toBe(true);
  });
});

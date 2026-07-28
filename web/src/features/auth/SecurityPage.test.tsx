import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { fireEvent, render, screen, within } from '@testing-library/react';
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
    expect(await screen.findByText('Password changed')).toBeInTheDocument();
    expect(screen.getByText('2 routine refreshes grouped')).toBeInTheDocument();
    expect(screen.queryByText('refresh', { exact: true })).not.toBeInTheDocument();
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
      return Promise.resolve([]);
    });

    renderPage();

    const revokeButton = await screen.findByRole('button', { name: 'Revoke access for Chrome on Windows' });
    fireEvent.click(revokeButton);
    const confirmation = screen.getByRole('alertdialog');
    expect(confirmation).toHaveTextContent('Revoke device access?');
    expect(apiMock).toHaveBeenCalledTimes(2);

    fireEvent.click(within(confirmation).getByRole('button', { name: 'Cancel' }));
    fireEvent.click(screen.getByRole('button', { name: 'Sign out everywhere' }));
    expect(screen.getByLabelText('Confirm with your current password')).toBeInTheDocument();
  });
});

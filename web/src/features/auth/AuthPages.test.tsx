import { api, setAccessToken } from '@/shared/api/client';
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { StrictMode } from 'react';
import { MemoryRouter } from 'react-router-dom';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { ThemeProvider } from '@/shared/theme/ThemeProvider';
import { SetupPassword } from './AuthPages';

vi.mock('@/shared/api/client', async (importOriginal) => {
  const original = await importOriginal<typeof import('@/shared/api/client')>();
  return { ...original, api: vi.fn(), setAccessToken: vi.fn() };
});

afterEach(() => {
  window.history.replaceState(null, '', '/admin/setup-password');
  vi.clearAllMocks();
});

describe('SetupPassword', () => {
  it('keeps the fragment token when StrictMode re-runs the mount effect', async () => {
    window.history.replaceState(null, '', '/admin/setup-password#token=setup-token-with-more-than-thirty-two-characters');
    vi.mocked(api).mockResolvedValue({
      access_token: 'access-token',
      expires_at: '2026-08-17T12:00:00Z',
      user: { id: 1, name: 'New staff', email: 'staff@example.com', role: 'staff', is_active: true, must_change_password: false },
      must_change_password: false,
    });
    const user = userEvent.setup();

    render(
      <StrictMode>
        <ThemeProvider>
          <MemoryRouter>
            <SetupPassword />
          </MemoryRouter>
        </ThemeProvider>
      </StrictMode>,
    );

    await user.type(screen.getByLabelText('New password (12+ characters)'), 'a sufficiently secure password');
    await user.click(screen.getByRole('button', { name: 'Activate account' }));

    await waitFor(() => expect(api).toHaveBeenCalledWith(
      '/auth/setup-password',
      expect.objectContaining({
        method: 'POST',
        body: JSON.stringify({
          token: 'setup-token-with-more-than-thirty-two-characters',
          password: 'a sufficiently secure password',
        }),
      }),
    ));
    expect(screen.queryByText('This setup link is invalid or expired. Ask an administrator for a new link.')).not.toBeInTheDocument();
    expect(setAccessToken).toHaveBeenCalledWith('access-token');
  });
});

import { api } from '@/shared/api/client';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router-dom';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { useMe } from '@/shared/hooks/useMe';
import Tanks from './TanksPage';

vi.mock('qrcode', () => ({
  default: { toDataURL: vi.fn().mockResolvedValue('data:image/png;base64,qr') },
}));

vi.mock('@/shared/api/client', async (importOriginal) => {
  const original = await importOriginal<typeof import('@/shared/api/client')>();
  return { ...original, api: vi.fn() };
});

vi.mock('@/shared/hooks/useMe', () => ({
  useMe: vi.fn(),
}));

const tanks = [
  {
    id: 1,
    public_id: 'tank-one',
    name: 'Display tank',
    location: 'Front room',
    description: null,
    is_public: false,
    customer_id: null,
    feeding_schedule: null,
    public_care_notes: null,
    tank_code: null,
    habitat_label: null,
    water_type: 'freshwater' as const,
    volume_liters: 180,
    established_on: null,
    hero_image_url: null,
    created_at: '2026-08-22T08:00:00Z',
    lifecycle: 'active' as const,
  },
];

const fleet = [
  {
    id: 1,
    name: 'Display tank',
    location: 'Front room',
    status: 'normal' as const,
  },
];

function renderPage() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <MemoryRouter initialEntries={['/admin/tanks']}>
        <Tanks />
      </MemoryRouter>
    </QueryClientProvider>,
  );
}

  describe('tank directory lifecycle', () => {
  beforeEach(() => {
    vi.mocked(api).mockReset();
    vi.mocked(useMe).mockReturnValue({
      data: {
        id: 1,
        name: 'Admin User',
        email: 'admin@example.test',
        role: 'admin',
        is_active: true,
        must_change_password: false,
      },
      isLoading: false,
      isError: false,
    } as unknown as ReturnType<typeof useMe>);
    vi.mocked(api).mockImplementation((path: string) => {
      if (path.startsWith('/tanks?lifecycle=')) return Promise.resolve(tanks);
      if (path === '/fleet') return Promise.resolve(fleet);
      return Promise.reject(new Error(`Unexpected path ${path}`));
    });
  });

  it('explains the retirement consequences and preserves historical records', async () => {
    const user = userEvent.setup();
    renderPage();

    await user.click(await screen.findByRole('button', { name: 'Retire Display tank' }));

    const dialog = screen.getByRole('alertdialog');
    expect(
      within(dialog).getByText(
        /registered devices will be disabled, while readings, alerts, assignments, equipment history, configuration, and media remain available/i,
      ),
    ).toBeInTheDocument();
    expect(screen.getByText('Private')).toBeInTheDocument();
    expect(screen.getByText('Not public')).toBeInTheDocument();
    expect(within(dialog).getByText(/Follow the hardware decommissioning checklist first/i)).toBeInTheDocument();
    expect(within(dialog).queryByText(/delete|erase|physical state/i)).not.toBeInTheDocument();
  });

  it('closes the QR dialog with Escape and restores focus to the QR action', async () => {
    const user = userEvent.setup();
    renderPage();

    const qrAction = await screen.findByRole('button', { name: 'Show QR code for Display tank' });
    await user.click(qrAction);
    expect(await screen.findByRole('dialog', { name: 'Display tank' })).toBeInTheDocument();

    await user.keyboard('{Escape}');
    await waitFor(() => expect(screen.queryByRole('dialog', { name: 'Display tank' })).not.toBeInTheDocument());
    expect(qrAction).toHaveFocus();
  });
});

import { ThemeProvider } from '@/shared/theme/ThemeProvider';
import { fireEvent, render, screen } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import ThemeControl from './ThemeControl';

function renderControl() {
  return render(
    <ThemeProvider>
      <ThemeControl />
    </ThemeProvider>,
  );
}

describe('ThemeControl', () => {
  beforeEach(() => {
    window.localStorage.clear();
    document.documentElement.removeAttribute('data-theme');
    document.documentElement.classList.remove('theme-ink-bleed');
    document.documentElement.style.colorScheme = '';
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it('follows a dark device preference when System is selected', () => {
    vi.stubGlobal('matchMedia', vi.fn().mockReturnValue({
      matches: true,
      addEventListener: vi.fn(),
      removeEventListener: vi.fn(),
    }));

    renderControl();

    expect(document.documentElement).toHaveAttribute('data-theme', 'dark');
    expect(screen.getByRole('button', { name: 'Theme: System' })).toBeInTheDocument();
  });

  it('lets visitors choose and persist the dark theme', () => {
    vi.stubGlobal('matchMedia', vi.fn().mockReturnValue({
      matches: false,
      addEventListener: vi.fn(),
      removeEventListener: vi.fn(),
    }));
    renderControl();

    fireEvent.click(screen.getByRole('button', { name: 'Theme: System' }));
    fireEvent.click(screen.getByRole('menuitemradio', { name: /^Dark/ }));

    expect(window.localStorage.getItem('aqualogic-theme')).toBe('dark');
    expect(document.documentElement).toHaveAttribute('data-theme', 'dark');
    expect(document.documentElement).toHaveClass('theme-ink-bleed');
    expect(screen.getByRole('button', { name: 'Theme: Dark' })).toBeInTheDocument();
  });

  it('restores the saved light theme and exposes the three theme modes', () => {
    window.localStorage.setItem('aqualogic-theme', 'light');
    renderControl();

    expect(document.documentElement).toHaveAttribute('data-theme', 'light');
    fireEvent.click(screen.getByRole('button', { name: 'Theme: Light' }));

    expect(screen.getAllByRole('menuitemradio')).toHaveLength(3);
    expect(screen.getByRole('menuitemradio', { name: /^Light/ })).toHaveAttribute('aria-checked', 'true');
  });
});

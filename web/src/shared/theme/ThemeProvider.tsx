import {
  createContext,
  type ReactNode,
  useCallback,
  useContext,
  useLayoutEffect,
  useMemo,
  useState,
} from 'react';

export const THEME_STORAGE_KEY = 'aqualogic-theme';

export const themeModes = ['system', 'light', 'dark'] as const;
export type ThemeMode = (typeof themeModes)[number];
export type ResolvedTheme = Exclude<ThemeMode, 'system'>;
export type ThemeChangeOptions = {
  origin?: { x: number; y: number; };
};

type ThemeContextValue = {
  mode: ThemeMode;
  resolvedTheme: ResolvedTheme;
  setMode: (mode: ThemeMode, options?: ThemeChangeOptions) => void;
};

const ThemeContext = createContext<ThemeContextValue | null>(null);

function isThemeMode(value: string | null): value is ThemeMode {
  return Boolean(value && themeModes.includes(value as ThemeMode));
}

export function getSystemTheme(): ResolvedTheme {
  if (typeof window === 'undefined' || typeof window.matchMedia !== 'function') return 'light';
  return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
}

export function resolveTheme(mode: ThemeMode): ResolvedTheme {
  return mode === 'system' ? getSystemTheme() : mode;
}

export function readStoredTheme(): ThemeMode {
  if (typeof window === 'undefined') return 'system';
  try {
    const stored = window.localStorage.getItem(THEME_STORAGE_KEY);
    return isThemeMode(stored) ? stored : 'system';
  } catch {
    return 'system';
  }
}

export function applyTheme(mode: ThemeMode): ResolvedTheme {
  const resolvedTheme = resolveTheme(mode);
  const root = document.documentElement;
  root.dataset.theme = resolvedTheme;
  root.style.colorScheme = resolvedTheme;
  const themeColor = document.querySelector<HTMLMetaElement>('meta[name="theme-color"]');
  if (themeColor) themeColor.content = resolvedTheme === 'dark' ? '#08161f' : '#0b2538';
  return resolvedTheme;
}

let themeBloomTimer: number | undefined;

function triggerThemeBloom(resolvedTheme: ResolvedTheme, origin?: { x: number; y: number; }) {
  if (!origin || typeof window === 'undefined' || typeof window.matchMedia !== 'function') return;
  if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;

  const root = document.documentElement;
  root.style.setProperty('--theme-ink-x', `${origin.x}px`);
  root.style.setProperty('--theme-ink-y', `${origin.y}px`);
  root.style.setProperty(
    '--theme-ink-color',
    resolvedTheme === 'dark' ? 'rgba(61, 194, 184, 0.16)' : 'rgba(8, 121, 112, 0.09)',
  );
  root.classList.remove('theme-ink-bleed');
  void root.offsetWidth;
  root.classList.add('theme-ink-bleed');
  if (themeBloomTimer) window.clearTimeout(themeBloomTimer);
  themeBloomTimer = window.setTimeout(() => {
    root.classList.remove('theme-ink-bleed');
  }, 470);
}

export function ThemeProvider({ children }: { children: ReactNode; }) {
  const [mode, setModeState] = useState<ThemeMode>(readStoredTheme);
  const [resolvedTheme, setResolvedTheme] = useState<ResolvedTheme>(() => resolveTheme(mode));

  useLayoutEffect(() => {
    const updateTheme = () => setResolvedTheme(applyTheme(mode));
    updateTheme();

    if (mode !== 'system' || typeof window.matchMedia !== 'function') return undefined;

    const mediaQuery = window.matchMedia('(prefers-color-scheme: dark)');
    const handleChange = () => updateTheme();
    if (mediaQuery.addEventListener) mediaQuery.addEventListener('change', handleChange);
    else mediaQuery.addListener?.(handleChange);
    return () => {
      if (mediaQuery.removeEventListener) mediaQuery.removeEventListener('change', handleChange);
      else mediaQuery.removeListener?.(handleChange);
    };
  }, [mode]);

  const setMode = useCallback((nextMode: ThemeMode, options?: ThemeChangeOptions) => {
    triggerThemeBloom(resolveTheme(nextMode), options?.origin);
    setModeState(nextMode);
    try {
      window.localStorage.setItem(THEME_STORAGE_KEY, nextMode);
    } catch {
      // Theme changes should still work when storage is unavailable.
    }
  }, []);

  const value = useMemo(
    () => ({ mode, resolvedTheme, setMode }),
    [mode, resolvedTheme, setMode],
  );

  return <ThemeContext.Provider value={value}>{children}</ThemeContext.Provider>;
}

export function useTheme() {
  const context = useContext(ThemeContext);
  if (!context) throw new Error('useTheme must be used within ThemeProvider');
  return context;
}

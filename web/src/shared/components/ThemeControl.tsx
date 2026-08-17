import { Monitor, Moon, Sun } from 'lucide-react';
import { useEffect, useRef, useState } from 'react';
import {
  themeModes,
  type ThemeMode,
  useTheme,
} from '@/shared/theme/ThemeProvider';
import './theme-control.css';

const modeLabels: Record<ThemeMode, string> = {
  system: 'System',
  light: 'Light',
  dark: 'Dark',
};

const modeDescriptions: Record<ThemeMode, string> = {
  system: 'Follow your device preference',
  light: 'Use the light interface',
  dark: 'Use the dark interface',
};

export function ThemeControl({ className = '' }: { className?: string; }) {
  const { mode, resolvedTheme, setMode } = useTheme();
  const [open, setOpen] = useState(false);
  const controlRef = useRef<HTMLDivElement>(null);
  const Icon = mode === 'system' ? Monitor : resolvedTheme === 'dark' ? Moon : Sun;

  useEffect(() => {
    if (!open) return undefined;

    const closeOnOutsidePointer = (event: PointerEvent) => {
      if (!controlRef.current?.contains(event.target as Node)) setOpen(false);
    };
    const closeOnEscape = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        setOpen(false);
        controlRef.current?.querySelector<HTMLButtonElement>('[aria-haspopup="menu"]')?.focus();
      }
    };

    document.addEventListener('pointerdown', closeOnOutsidePointer);
    document.addEventListener('keydown', closeOnEscape);
    return () => {
      document.removeEventListener('pointerdown', closeOnOutsidePointer);
      document.removeEventListener('keydown', closeOnEscape);
    };
  }, [open]);

  const chooseTheme = (themeMode: ThemeMode) => {
    const trigger = controlRef.current?.querySelector<HTMLButtonElement>('[aria-haspopup="menu"]');
    const bounds = trigger?.getBoundingClientRect();
    if (mode !== themeMode) {
      setMode(themeMode, bounds
        ? { origin: { x: bounds.left + bounds.width / 2, y: bounds.top + bounds.height / 2 } }
        : undefined);
    }
    setOpen(false);
  };

  return (
    <div className={`theme-control ${className}`.trim()} ref={controlRef}>
      <button
        className="theme-control-trigger icon-button"
        type="button"
        aria-label={`Theme: ${modeLabels[mode]}`}
        aria-expanded={open}
        aria-haspopup="menu"
        title={`Theme: ${modeLabels[mode]}`}
        onClick={() => setOpen((value) => !value)}
      >
        <Icon size={17} aria-hidden="true" />
      </button>
      {open && (
        <div className="theme-control-menu" role="menu" aria-label="Choose color theme">
          <div className="theme-control-menu-heading">
            <strong>Appearance</strong>
            <small>Choose how AquaLogic looks</small>
          </div>
          {themeModes.map((themeMode) => {
            const ModeIcon = themeMode === 'system' ? Monitor : themeMode === 'dark' ? Moon : Sun;
            return (
              <button
                className={`theme-control-option ${mode === themeMode ? 'selected' : ''}`}
                key={themeMode}
                type="button"
                role="menuitemradio"
                aria-checked={mode === themeMode}
                onClick={() => chooseTheme(themeMode)}
              >
                <ModeIcon size={16} aria-hidden="true" />
                <span>
                  <strong>{modeLabels[themeMode]}</strong>
                  <small>{modeDescriptions[themeMode]}</small>
                </span>
                {mode === themeMode && <span className="theme-control-check" aria-hidden="true">✓</span>}
              </button>
            );
          })}
        </div>
      )}
    </div>
  );
}

export default ThemeControl;

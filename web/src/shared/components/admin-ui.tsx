import { statusText } from '@/shared/api/client';
import { AlertTriangle, CheckCircle2, Inbox, X } from 'lucide-react';
import {
  FormEvent,
  ReactNode,
  RefObject,
  useEffect,
  useMemo,
  useRef,
  useState,
} from 'react';
import { createPortal } from 'react-dom';

export type FleetStatus = 'normal' | 'warning' | 'critical' | 'offline';

export const fleetStatusOrder: FleetStatus[] = [
  'normal',
  'warning',
  'critical',
  'offline',
];

export function statusLabel(value: string) {
  return value.charAt(0).toUpperCase() + value.slice(1).replaceAll('_', ' ');
}

export function StatusBadge({ value }: { value: string; }) {
  return (
    <span className={`status-badge status-${value}`} aria-label={statusText(value)}>
      <span className="status-dot" aria-hidden="true" />
      {statusLabel(value)}
    </span>
  );
}

export function PageHeader({
  eyebrow,
  title,
  description,
  actions,
}: {
  eyebrow?: string;
  title: string;
  description?: string;
  actions?: ReactNode;
}) {
  return (
    <div className="page-header">
      <div>
        {eyebrow && <p className="eyebrow">{eyebrow}</p>}
        <h1>{title}</h1>
        {description && <p className="page-description">{description}</p>}
      </div>
      {actions && <div className="page-actions">{actions}</div>}
    </div>
  );
}

export function Panel({
  title,
  description,
  action,
  children,
  className = '',
}: {
  title?: string;
  description?: string;
  action?: ReactNode;
  children: ReactNode;
  className?: string;
}) {
  return (
    <section className={`panel ${className}`.trim()}>
      {(title || description || action) && (
        <header className="panel-header">
          <div>
            {title && <h2>{title}</h2>}
            {description && <p>{description}</p>}
          </div>
          {action}
        </header>
      )}
      {children}
    </section>
  );
}

export function LoadingState({ label = 'Loading data…' }: { label?: string; }) {
  return (
    <div className="state-block" role="status">
      <span className="spinner" aria-hidden="true" />
      <p>{label}</p>
    </div>
  );
}

export function EmptyState({
  title,
  message,
}: {
  title: string;
  message: string;
}) {
  return (
    <div className="state-block">
      <span className="state-icon" aria-hidden="true">
        <Inbox size={20} />
      </span>
      <strong>{title}</strong>
      <p>{message}</p>
    </div>
  );
}

export function ErrorState({
  message,
  retry,
}: {
  message: string;
  retry?: () => void;
}) {
  return (
    <div className="state-block state-error" role="alert">
      <span className="state-icon" aria-hidden="true">
        <AlertTriangle size={20} />
      </span>
      <strong>Something went wrong</strong>
      <p>{message}</p>
      {retry && (
        <button className="button button-secondary" type="button" onClick={retry}>
          Try again
        </button>
      )}
    </div>
  );
}

export function Notice({
  children,
  tone = 'success',
}: {
  children: ReactNode;
  tone?: 'success' | 'warning' | 'error';
}) {
  return (
    <div className={`notice notice-${tone}`} role={tone === 'error' ? 'alert' : 'status'}>
      {tone === 'success' && <CheckCircle2 size={18} aria-hidden="true" />}
      {tone !== 'success' && <AlertTriangle size={18} aria-hidden="true" />}
      <span>{children}</span>
    </div>
  );
}

export function Toast({
  message,
  tone = 'success',
  onDismiss,
  autoDismissMs = 4_500,
}: {
  message: ReactNode;
  tone?: 'success' | 'warning' | 'error';
  onDismiss: () => void;
  autoDismissMs?: number;
}) {
  const dismissRef = useRef(onDismiss);
  dismissRef.current = onDismiss;

  useEffect(() => {
    if (!message || autoDismissMs <= 0) return;
    const timeout = window.setTimeout(() => dismissRef.current(), autoDismissMs);
    return () => window.clearTimeout(timeout);
  }, [autoDismissMs, message]);

  if (!message) return null;

  return createPortal(
    <div
      className={`admin-toast admin-toast-${tone}`}
      role={tone === 'error' ? 'alert' : 'status'}
      aria-live={tone === 'error' ? 'assertive' : 'polite'}
      aria-atomic="true"
    >
      {tone === 'success' ? <CheckCircle2 size={19} aria-hidden="true" /> : <AlertTriangle size={19} aria-hidden="true" />}
      <span>{message}</span>
      <button className="admin-toast-dismiss" type="button" onClick={onDismiss} aria-label="Dismiss notification">
        <X size={16} aria-hidden="true" />
      </button>
    </div>,
    document.body,
  );
}

const focusableSelector =
  'button:not([disabled]), [href], input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])';

function useModalFocus(open: boolean, onClose: () => void, ref: RefObject<HTMLElement>) {
  const returnFocus = useRef<HTMLElement | null>(null);
  const closeRef = useRef(onClose);
  closeRef.current = onClose;

  useEffect(() => {
    if (!open) return;
    returnFocus.current = document.activeElement as HTMLElement | null;
    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    const frame = window.requestAnimationFrame(() => {
      const initialFocus = ref.current?.querySelector<HTMLElement>('[data-drawer-close]')
        ?? ref.current?.querySelector<HTMLElement>(focusableSelector);
      initialFocus?.focus();
    });

    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        event.preventDefault();
        closeRef.current();
        return;
      }
      if (event.key !== 'Tab') return;
      const items = Array.from(
        ref.current?.querySelectorAll<HTMLElement>(focusableSelector) ?? [],
      ).filter((item) => !item.hasAttribute('disabled'));
      if (!items.length) return;
      const first = items[0];
      const last = items[items.length - 1];
      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault();
        first.focus();
      }
    };

    document.addEventListener('keydown', onKeyDown);
    return () => {
      window.cancelAnimationFrame(frame);
      document.removeEventListener('keydown', onKeyDown);
      document.body.style.overflow = previousOverflow;
      returnFocus.current?.focus();
    };
  }, [open, ref]);
}

function useDeferredDrawerContent(open: boolean) {
  const [ready, setReady] = useState(false);

  useEffect(() => {
    if (!open) {
      setReady(false);
      return;
    }
    let secondFrame = 0;
    const firstFrame = window.requestAnimationFrame(() => {
      secondFrame = window.requestAnimationFrame(() => setReady(true));
    });
    return () => {
      window.cancelAnimationFrame(firstFrame);
      window.cancelAnimationFrame(secondFrame);
    };
  }, [open]);

  return ready;
}

export function Drawer({
  open,
  title,
  description,
  onClose,
  children,
  footer,
}: {
  open: boolean;
  title: string;
  description?: string;
  onClose: () => void;
  children: ReactNode;
  footer?: ReactNode;
}) {
  const drawerRef = useRef<HTMLElement>(null);
  useModalFocus(open, onClose, drawerRef);
  const contentReady = useDeferredDrawerContent(open);
  if (!open) return null;

  return (
    <div className="modal-layer">
      <button
        className="modal-backdrop"
        type="button"
        onClick={onClose}
        aria-label={`Close ${title}`}
      />
      <aside
        className="drawer"
        ref={drawerRef}
        role="dialog"
        aria-modal="true"
        aria-labelledby="drawer-title"
        data-drawer
      >
        <header className="drawer-header">
          <div>
            <p className="eyebrow">AquaLogic management</p>
            <h2 id="drawer-title">{title}</h2>
            {description && <p>{description}</p>}
          </div>
          <button className="icon-button" type="button" onClick={onClose} aria-label="Close" data-drawer-close>
            <X size={20} />
          </button>
        </header>
        <div className={`drawer-body${contentReady ? '' : ' drawer-body-deferred'}`} aria-busy={!contentReady}>
          {contentReady ? children : <span className="drawer-loading-line" aria-hidden="true" />}
        </div>
        {footer && <footer className="drawer-footer">{footer}</footer>}
      </aside>
    </div>
  );
}

export function ConfirmDialog({
  open,
  title,
  message,
  confirmLabel,
  onConfirm,
  onClose,
  busy = false,
  tone = 'danger',
}: {
  open: boolean;
  title: string;
  message: string;
  confirmLabel: string;
  onConfirm: () => void;
  onClose: () => void;
  busy?: boolean;
  tone?: 'danger' | 'primary';
}) {
  const dialogRef = useRef<HTMLElement>(null);
  useModalFocus(open, onClose, dialogRef);
  if (!open) return null;
  return (
    <div className="modal-layer modal-centered">
      <button className="modal-backdrop" type="button" onClick={onClose} aria-label="Cancel" />
      <section
        className="confirm-dialog"
        ref={dialogRef}
        role="alertdialog"
        aria-modal="true"
        aria-labelledby="confirm-title"
        aria-describedby="confirm-message"
      >
        <span className={`confirm-icon confirm-${tone}`} aria-hidden="true">
          <AlertTriangle size={22} />
        </span>
        <h2 id="confirm-title">{title}</h2>
        <p id="confirm-message">{message}</p>
        <div className="dialog-actions">
          <button className="button button-secondary" type="button" onClick={onClose}>
            Cancel
          </button>
          <button
            className={`button ${tone === 'danger' ? 'button-danger' : 'button-primary'}`}
            type="button"
            onClick={onConfirm}
            disabled={busy}
          >
            {busy ? 'Working…' : confirmLabel}
          </button>
        </div>
      </section>
    </div>
  );
}

export function SearchField({
  value,
  onChange,
  placeholder,
}: {
  value: string;
  onChange: (value: string) => void;
  placeholder: string;
}) {
  return (
    <label className="search-field">
      <span className="sr-only">Search</span>
      <input
        type="search"
        value={value}
        onChange={(event) => onChange(event.target.value)}
        placeholder={placeholder}
      />
    </label>
  );
}

export function submitFormById(id: string) {
  const form = document.getElementById(id) as HTMLFormElement | null;
  form?.requestSubmit();
}

export function preventDefault(handler: () => void) {
  return (event: FormEvent) => {
    event.preventDefault();
    handler();
  };
}

export function useFilteredList<T>(
  items: T[] | undefined,
  query: string,
  values: (item: T) => Array<string | undefined | null>,
) {
  return useMemo(() => {
    const normalized = query.trim().toLowerCase();
    if (!normalized) return items ?? [];
    return (items ?? []).filter((item) =>
      values(item).some((value) => value?.toLowerCase().includes(normalized)),
    );
  }, [items, query, values]);
}

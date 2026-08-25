import { statusText } from '@/shared/api/client';
import { AlertTriangle, CheckCircle2, CircleHelp, CircleOff, CirclePause, CirclePlay, Inbox, Radio, WifiOff, X } from 'lucide-react';
import {
  FormEvent,
  cloneElement,
  type ReactElement,
  ReactNode,
  useEffect,
  useId,
  useMemo,
  useRef,
  useState,
} from 'react';
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogOverlay,
  AlertDialogPortal,
  AlertDialogTitle,
} from '@/shared/components/ui/alert-dialog';
import {
  Dialog,
  DialogClose,
  DialogContent,
  DialogDescription,
  DialogOverlay,
  DialogPortal,
  DialogTitle,
} from '@/shared/components/ui/dialog';

export type FleetStatus = 'normal' | 'warning' | 'critical' | 'offline';

export const fleetStatusOrder: FleetStatus[] = [
  'normal',
  'warning',
  'critical',
  'offline',
];

export function statusLabel(value: string) {
  const labels: Record<string, string> = {
    suitable: 'Water suitable',
    attention: 'Water needs attention',
    unavailable: 'Water data unavailable',
  };
  return labels[value] ?? value.charAt(0).toUpperCase() + value.slice(1).replaceAll('_', ' ');
}

export function StatusBadge({ value }: { value: string; }) {
  return (
    <span className={`status-badge status-${value}`} aria-label={statusText(value)}>
      <span className="status-dot" aria-hidden="true" />
      {statusLabel(value)}
    </span>
  );
}

/** Water-health state only. It deliberately does not represent lifecycle or device state. */
export function OperationalStatusBadge({ value }: { value: FleetStatus }) {
  const icons = { normal: CheckCircle2, warning: AlertTriangle, critical: AlertTriangle, offline: WifiOff };
  const Icon = icons[value];
  return (
    <span className={`status-badge status-${value}`} aria-label={statusText(value)}>
      <Icon size={13} aria-hidden="true" />
      {statusLabel(value)}
    </span>
  );
}

/** Tank lifecycle is intentionally neutral: retired is not an offline reading. */
export function TankLifecycleBadge({ lifecycle }: { lifecycle: 'active' | 'retired' }) {
  const retired = lifecycle === 'retired';
  return (
    <span className={`status-badge ${retired ? 'status-retired' : 'status-normal'}`} aria-label={retired ? 'Tank retired' : 'Tank active'}>
      {retired ? <CirclePause size={13} aria-hidden="true" /> : <CirclePlay size={13} aria-hidden="true" />}
      {retired ? 'Retired' : 'Active'}
    </span>
  );
}

export function DeviceConnectionBadge({ status }: { status: 'online' | 'offline' | 'disabled' }) {
  const definitions = {
    online: { label: 'Online', className: 'status-normal', Icon: Radio },
    offline: { label: 'Offline', className: 'status-offline', Icon: WifiOff },
    disabled: { label: 'Disabled', className: 'status-disabled', Icon: CircleOff },
  } as const;
  const { label, className, Icon } = definitions[status];
  return <span className={`status-badge ${className}`} aria-label={`Device ${label.toLowerCase()}`}><Icon size={13} aria-hidden="true" />{label}</span>;
}

export function CommandStatusBadge({ status }: { status: 'queued' | 'executing' | 'succeeded' | 'failed' | 'expired' | 'outcome_unknown' }) {
  const definitions = {
    queued: ['Queued', 'status-warning', CircleHelp],
    executing: ['Executing', 'status-command-executing', Radio],
    succeeded: ['Succeeded', 'status-normal', CheckCircle2],
    failed: ['Failed', 'status-critical', AlertTriangle],
    expired: ['Expired', 'status-offline', CircleOff],
    outcome_unknown: ['Outcome unknown', 'status-command-unknown', CircleHelp],
  } as const;
  const [label, className, Icon] = definitions[status];
  return <span className={`status-badge ${className}`} aria-label={`Command ${label.toLowerCase()}`}><Icon size={13} aria-hidden="true" />{label}</span>;
}

export type AccountLifecycleStatus = 'active' | 'setup_required' | 'inactive';

const accountLifecycleLabels: Record<AccountLifecycleStatus, string> = {
  active: 'Active',
  setup_required: 'Password setup required',
  inactive: 'Inactive',
};

export function LifecycleBadge({ status }: { status: AccountLifecycleStatus; }) {
  const visualStatus = status === 'active' ? 'normal' : status === 'setup_required' ? 'warning' : 'offline';
  const label = accountLifecycleLabels[status];
  return (
    <span className={`status-badge status-${visualStatus}`} aria-label={label}>
      <span className="status-dot" aria-hidden="true" />
      {label}
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

/**
 * A compact AquaLogic field composition for forms that need consistent labels,
 * help, units, and accessible validation without forcing a form-library rewrite.
 */
export function FormField({
  label,
  children,
  description,
  error,
  required = false,
  suffix,
  disabled = false,
  busy = false,
  className = '',
}: {
  label: string;
  children: ReactElement<{ id?: string; disabled?: boolean; 'aria-describedby'?: string; 'aria-invalid'?: boolean }>;
  description?: ReactNode;
  error?: string;
  required?: boolean;
  suffix?: ReactNode;
  disabled?: boolean;
  busy?: boolean;
  className?: string;
}) {
  const inputId = useId();
  const descriptionId = useId();
  const errorId = useId();
  const describedBy = [description ? descriptionId : null, error ? errorId : null].filter(Boolean).join(' ') || undefined;
  const control = cloneElement(children, {
    id: children.props.id ?? inputId,
    disabled: children.props.disabled ?? (disabled || busy),
    'aria-describedby': children.props['aria-describedby'] ?? describedBy,
    'aria-invalid': error ? true : children.props['aria-invalid'],
  });
  const controlId = control.props.id;

  return (
    <div className={`form-field field${error ? ' has-error' : ''}${busy ? ' is-busy' : ''}${className ? ` ${className}` : ''}`}>
      <label className="form-field-label" htmlFor={controlId}>
        {label}{required && <span className="form-field-required" aria-hidden="true"> *</span>}
      </label>
      <div className="form-field-control">
        {control}
        {suffix && <span className="form-field-suffix" aria-hidden="true">{suffix}</span>}
      </div>
      {description && <small className="form-field-description" id={descriptionId}>{description}</small>}
      {error && <small className="form-field-error" id={errorId} role="alert">{error}</small>}
    </div>
  );
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
  const contentReady = useDeferredDrawerContent(open);
  const returnFocus = useRef<HTMLElement | null>(null);
  useEffect(() => {
    if (open) returnFocus.current = document.activeElement as HTMLElement | null;
  }, [open]);
  return (
    <Dialog open={open} onOpenChange={(next) => { if (!next) onClose(); }}>
      <DialogPortal>
        <div className="modal-layer">
          <DialogOverlay />
          <DialogContent
            className="drawer"
            aria-describedby={description ? 'drawer-description' : undefined}
            onCloseAutoFocus={(event) => {
              event.preventDefault();
              returnFocus.current?.focus();
            }}
          >
        <header className="drawer-header">
          <div>
            <p className="eyebrow">AquaLogic management</p>
            <DialogTitle>{title}</DialogTitle>
            {description && <DialogDescription id="drawer-description">{description}</DialogDescription>}
          </div>
          <DialogClose className="icon-button" type="button" aria-label="Close" data-drawer-close>
            <X size={20} />
          </DialogClose>
        </header>
        <div className={`drawer-body${contentReady ? '' : ' drawer-body-deferred'}`} aria-busy={!contentReady}>
          {contentReady ? children : <span className="drawer-loading-line" aria-hidden="true" />}
        </div>
        {footer && <footer className="drawer-footer">{footer}</footer>}
          </DialogContent>
        </div>
      </DialogPortal>
    </Dialog>
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
  children,
}: {
  open: boolean;
  title: string;
  message: string;
  confirmLabel: string;
  onConfirm: () => void;
  onClose: () => void;
  busy?: boolean;
  tone?: 'danger' | 'primary';
  children?: ReactNode;
}) {
  return (
    <AlertDialog open={open} onOpenChange={(next) => { if (!next) onClose(); }}>
      <AlertDialogPortal>
        <div className="modal-layer modal-centered">
          <AlertDialogOverlay />
          <AlertDialogContent className="confirm-dialog">
        <span className={`confirm-icon confirm-${tone}`} aria-hidden="true">
          <AlertTriangle size={22} />
        </span>
        <AlertDialogTitle>{title}</AlertDialogTitle>
        <AlertDialogDescription>{message}</AlertDialogDescription>
        {children}
        <div className="dialog-actions">
          <AlertDialogCancel className="button button-secondary" type="button">
            Cancel
          </AlertDialogCancel>
          <AlertDialogAction
            className={`button ${tone === 'danger' ? 'button-danger' : 'button-primary'}`}
            type="button"
            onClick={onConfirm}
            disabled={busy}
          >
            {busy ? 'Working…' : confirmLabel}
          </AlertDialogAction>
        </div>
          </AlertDialogContent>
        </div>
      </AlertDialogPortal>
    </AlertDialog>
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

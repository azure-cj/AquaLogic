import {
  AlertTriangle,
  CheckCircle2,
  Info,
  LoaderCircle,
  X,
  XCircle,
} from 'lucide-react';
import { Toaster as Sonner, type ToasterProps } from 'sonner';
import 'sonner/dist/styles.css';
import { useTheme } from '@/shared/theme/ThemeProvider';

const defaultToastClassNames = {
  toast: 'aqualogic-toast',
  title: 'aqualogic-toast-title',
  description: 'aqualogic-toast-description',
  closeButton: 'aqualogic-toast-close',
  actionButton: 'aqualogic-toast-action',
  cancelButton: 'aqualogic-toast-cancel',
};

const defaultIcons = {
  success: <CheckCircle2 size={18} aria-hidden="true" />,
  info: <Info size={18} aria-hidden="true" />,
  warning: <AlertTriangle size={18} aria-hidden="true" />,
  error: <XCircle size={18} aria-hidden="true" />,
  loading: <LoaderCircle size={18} aria-hidden="true" className="aqualogic-toast-loader" />,
  close: <X size={16} aria-hidden="true" />,
};

export function Toaster(props: ToasterProps) {
  const { resolvedTheme } = useTheme();
  const className = ['aqualogic-toaster', props.className].filter(Boolean).join(' ');

  return (
    <Sonner
      {...props}
      className={className}
      theme={resolvedTheme}
      position={props.position ?? 'top-right'}
      richColors={props.richColors ?? true}
      closeButton={props.closeButton ?? true}
      expand={props.expand ?? false}
      visibleToasts={props.visibleToasts ?? 4}
      duration={props.duration ?? 4_500}
      offset={props.offset ?? {
        top: 'calc(env(safe-area-inset-top, 0px) + 6rem)',
        right: 'max(1rem, env(safe-area-inset-right))',
      }}
      mobileOffset={props.mobileOffset ?? {
        top: 'calc(env(safe-area-inset-top, 0px) + 4.5rem)',
        right: 'max(.75rem, env(safe-area-inset-right))',
        left: 'max(.75rem, env(safe-area-inset-left))',
      }}
      customAriaLabel={props.customAriaLabel ?? 'AquaLogic notifications'}
      containerAriaLabel={props.containerAriaLabel ?? 'AquaLogic notifications'}
      icons={{ ...defaultIcons, ...props.icons }}
      toastOptions={{
        duration: props.toastOptions?.duration ?? 4_500,
        closeButtonAriaLabel: props.toastOptions?.closeButtonAriaLabel ?? 'Dismiss notification',
        ...props.toastOptions,
        classNames: {
          ...defaultToastClassNames,
          ...props.toastOptions?.classNames,
        },
      }}
    />
  );
}

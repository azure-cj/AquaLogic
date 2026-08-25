import { toast, type ExternalToast } from 'sonner';
import type { ReactNode } from 'react';

const withDuration = (options: ExternalToast | undefined, duration: number): ExternalToast => ({
  duration,
  ...options,
});

export const notify = {
  success(message: ReactNode, options?: ExternalToast) {
    return toast.success(message, withDuration(options, 4_500));
  },
  info(message: ReactNode, options?: ExternalToast) {
    return toast.info(message, withDuration(options, 4_500));
  },
  warning(message: ReactNode, options?: ExternalToast) {
    return toast.warning(message, withDuration(options, 4_500));
  },
  error(message: ReactNode, options?: ExternalToast) {
    return toast.error(message, withDuration(options, Infinity));
  },
  loading(message: ReactNode, options?: ExternalToast) {
    return toast.loading(message, withDuration(options, Infinity));
  },
  promise: toast.promise,
  dismiss(id?: number | string) {
    return toast.dismiss(id);
  },
};

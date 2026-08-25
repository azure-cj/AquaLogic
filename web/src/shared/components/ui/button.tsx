import { cva, type VariantProps } from 'class-variance-authority';
import { cn } from '@/shared/lib/utils';
import type { ButtonHTMLAttributes, ReactNode } from 'react';

const buttonVariants = cva('button', {
  variants: {
    variant: {
      primary: 'button-primary',
      secondary: 'button-secondary',
      danger: 'button-danger',
      quietDanger: 'button-quiet-danger',
      quiet: 'button-quiet',
    },
    size: { default: '', small: 'button-small', icon: 'icon-button' },
  },
  defaultVariants: { variant: 'primary', size: 'default' },
});

export interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement>, VariantProps<typeof buttonVariants> {
  children: ReactNode;
}

/** Branded button base; its visual treatment remains in shared-admin.css. */
export function Button({ className, variant, size, type = 'button', ...props }: ButtonProps) {
  return <button type={type} className={cn(buttonVariants({ variant, size }), className)} {...props} />;
}

import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';

/** Combine conditional classes without changing the existing CSS-first UI system. */
export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

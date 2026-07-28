export const formatDate = (value?: string | null) =>
  value
    ? new Intl.DateTimeFormat('en-PH', {
      dateStyle: 'medium',
      timeStyle: 'short',
      timeZone: 'Asia/Manila',
    }).format(new Date(value))
    : 'No reading';

export const relativeTime = (value?: string | null) => {
  if (!value) return 'No report';
  const seconds = Math.max(
    0,
    Math.round((Date.now() - new Date(value).getTime()) / 1000),
  );
  if (seconds < 60) return `${seconds}s ago`;
  const minutes = Math.round(seconds / 60);
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.round(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  return `${Math.round(hours / 24)}d ago`;
};

export const initials = (name: string) =>
  name
    .split(/\s+/)
    .map((part) => part[0])
    .join('')
    .slice(0, 2)
    .toUpperCase();

export const formatReading = (
  value: number | null | undefined,
  unit: string,
  digits = 1,
) => (value == null ? '—' : `${value.toFixed(digits)}${unit ? ` ${unit}` : ''}`);

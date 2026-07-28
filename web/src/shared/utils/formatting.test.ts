import { describe, expect, it, vi } from 'vitest';
import { formatDate, formatReading, initials, relativeTime } from './formatting';

describe('formatting utilities', () => {
  it('formats readings and initials consistently', () => {
    expect(formatReading(24.456, '°C', 1)).toBe('24.5 °C');
    expect(formatReading(null, 'ppm')).toBe('—');
    expect(initials('AquaLogic Demo')).toBe('AD');
  });

  it('uses Manila-local dates and concise relative times', () => {
    vi.setSystemTime(new Date('2026-07-26T12:00:00Z'));
    expect(formatDate('2026-07-26T00:00:00Z')).toContain('Jul');
    expect(relativeTime('2026-07-26T11:55:00Z')).toBe('5m ago');
    vi.useRealTimers();
  });
});

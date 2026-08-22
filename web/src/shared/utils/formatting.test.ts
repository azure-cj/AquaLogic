import { describe, expect, it, vi } from 'vitest';
import {
  formatDate,
  formatReading,
  formatReportingAge,
  initials,
  relativeTime,
  reportingAgeSeconds,
} from './formatting';

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

  it('formats short, long, and missing server-report ages', () => {
    expect(formatReportingAge(12)).toBe('Reported approximately 12 seconds ago');
    expect(formatReportingAge(13 * 60 * 60, { offline: true })).toBe('No report for approximately 13 hours');
    expect(formatReportingAge(null, { offline: true })).toBe('No report received');
  });

  it('derives reporting age from receipt time rather than observation time', () => {
    const now = Date.parse('2026-08-22T12:00:00Z');
    expect(reportingAgeSeconds('2026-08-22T11:59:48Z', now)).toBe(12);
    expect(reportingAgeSeconds(null, now)).toBeNull();
  });
});

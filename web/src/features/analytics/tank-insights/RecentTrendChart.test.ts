import { describe, expect, it } from 'vitest';
import { niceAxis } from './RecentTrendChart';

describe('niceAxis', () => {
  it.each([[21.4, 28.9, 2], [6.62, 7.83, .5], [118, 214, 50], [2.61, 2.79, .05]])('uses round 1/2/5 steps for %s–%s', (low, high, step) => {
    const { domain, ticks } = niceAxis(low, high);
    expect(domain[0]).toBeLessThanOrEqual(low);
    expect(domain[1]).toBeGreaterThanOrEqual(high);
    expect(ticks[1] - ticks[0]).toBeCloseTo(step);
    expect(ticks[0]).toBe(domain[0]);
    expect(ticks[ticks.length - 1]).toBeCloseTo(domain[1]);
  });
});

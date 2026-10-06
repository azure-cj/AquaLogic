import { describe, expect, it } from 'vitest';
import { crossingTimeCopy, formatRate, headroomCopy, projectionCopy, speciesCopy, stabilityCopy, trendCopy } from './CopyFormatter';
import { parameterFixture } from './currentInsights.fixture';
import type { CurrentProjection, CurrentStability, CurrentTrend } from '../types';

describe('Part A copy formatter', () => {
  const p = parameterFixture();
  it.each<[CurrentTrend['status'], string]>([
    ['rising', 'Rising 0.18 °C/h over the last 6 h'], ['falling', 'Falling 0.18 °C/h over the last 6 h'],
    ['steady', 'Steady over the last 6 h'], ['uncertain', 'No clear direction — readings vary'],
    ['insufficient_data', 'Not enough recent readings (12 of 10 half-hour intervals)'],
  ])('formats trend %s', (status, expected) => expect(trendCopy({ ...p.trend, status, rate_per_hour: status === 'falling' ? -.18 : .18 }, '°C')).toBe(expected));
  it.each<[CurrentTrend['reason'], string]>([
    ['too_few_buckets', 'Not enough recent readings (3 of 10 half-hour intervals)'],
    ['gap', 'Recent readings have a gap over 1 hour'], ['not_recent', 'No readings in the last half hour'],
    ['mixed_source', 'Readings come from more than one source'],
  ])('formats insufficient trend reason %s', (reason, expected) => expect(trendCopy({ ...p.trend, status: 'insufficient_data', reason, qualifying_buckets: 3 }, '°C')).toBe(expected));
  it('formats both headroom sides, outside, disabled, missing bound and missing value', () => {
    expect(headroomCopy(p.headroom, '°C')).toBe('1 °C from the upper warning bound (28 °C)');
    expect(headroomCopy({ ...p.headroom!, side: 'lower', distance: 3, bound: 24 }, '°C')).toBe('3 °C from the lower warning bound (24 °C)');
    expect(headroomCopy({ ...p.headroom!, outside: true, distance: -1 }, '°C')).toBe('Outside the warning range');
    expect(headroomCopy(null, '°C')).toBe('Warning thresholds disabled');
    expect(headroomCopy({ ...p.headroom!, bound: null, distance: null, reason: 'side_bound_missing' }, '°C')).toBe('No warning bound configured on this side');
    expect(headroomCopy({ ...p.headroom!, distance: null, reason: 'value_unavailable' }, '°C')).toBe('No observed value to assess warning headroom');
  });
  it.each<[CurrentProjection['status'], string]>([
    ['crossing_projected', 'If the current trend continues, may reach the upper warning bound (28 °C) in about 2–2.5 h'],
    ['no_crossing_within_horizon', 'Not projected to reach a warning bound within 3 h if the trend continues'],
    ['too_uncertain', 'Trend too uncertain to project'], ['stale', 'No projection: the latest reading is not current'],
    ['insufficient_data', 'No projection: not enough recent readings'], ['already_outside', 'Already outside the warning range — see alerts'],
    ['no_bound', 'No warning bound configured on this side'], ['not_applicable', 'Turbidity is not projected because it changes in sudden events'],
  ])('formats projection %s', (status, expected) => expect(projectionCopy({ ...p.projection, status }, '°C')).toBe(expected));
  it.each([
    [1.9, 2.7, 'in about 2–2.5 h'], [.4, .6, 'in about 0.5 h'], [.1, .6, 'within about 0.5 h'],
    [.1, .2, 'soon; the latest readings are close to the bound'], [1.9, null, 'in about 2 h or later'],
    [0, null, 'in about 0 h or later'], [null, null, 'at an unavailable time'],
  ])('rounds crossing range %s, %s', (low, high, expected) => expect(crossingTimeCopy(low as number | null, high as number | null)).toBe(expected));
  it('formats lower crossings and rates to two decimal places', () => {
    expect(projectionCopy({ ...p.projection, bound_side: 'lower', bound: 24, crossing_hours_high: null }, '°C')).toBe('If the current trend continues, may reach the lower warning bound (24 °C) in about 2 h or later');
    expect(formatRate(-.1849)).toBe('0.18'); expect(formatRate(12.345)).toBe('12.35');
  });
  it.each<[CurrentStability['status'], string]>([
    ['more_variable', 'More variable than usual (1.1× its 7-day baseline)'], ['steadier', 'Steadier than usual (1.1× its 7-day baseline)'],
    ['typical', 'Typical variability for this tank'], ['insufficient_data', 'Not enough readings in the last 24 h'],
    ['insufficient_baseline', 'Baseline needs 5 days of readings (7 available)'],
  ])('formats stability %s', (status, expected) => expect(stabilityCopy({ ...p.stability, status })).toBe(expected));
  it('formats every species state including unavailable compliance without inventing a percentage', () => {
    expect(speciesCopy(p.species_range, '°C')).toBe("91.5% of the last 24 h within the assigned species' range (24–28 °C)");
    expect(speciesCopy({ ...p.species_range, status: 'conflict', conflict: { min_species: 'Discus', min: 28, max_species: 'Corydoras', max: 27 } }, '°C')).toBe("Assigned species' ranges do not overlap: Discus needs at least 28, Corydoras needs at most 27");
    expect(speciesCopy({ ...p.species_range, status: 'not_configured' }, '°C')).toBe('No species range configured');
    expect(speciesCopy({ ...p.species_range, status: 'not_applicable' }, 'NTU')).toBe('Turbidity has no species range');
    expect(speciesCopy({ ...p.species_range, compliance_percent_24h: null, compliance_readings: 3, compliance_reason: 'too_few_readings' }, '°C')).toBe("Assigned species' range (24–28 °C); not enough readings to assess the last 24 h (3 of 30)");
    expect(speciesCopy({ ...p.species_range, compliance_percent_24h: null, compliance_reason: 'mixed_source' }, '°C')).toBe("Assigned species' range (24–28 °C); readings come from more than one source");
    expect(speciesCopy({ ...p.species_range, min: null }, '°C')).toContain('unbounded–28');
  });
});

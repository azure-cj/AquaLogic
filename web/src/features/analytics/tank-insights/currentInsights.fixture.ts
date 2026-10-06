// Test fixtures for the staff-only API contract; not imported by application code.
import type { CurrentInsightsResponse, CurrentParameter, CurrentParameterInsights, CurrentTankInsights } from '../types';

export function parameterFixture(parameter: CurrentParameter = 'temperature'): CurrentParameterInsights {
  const unit = { temperature: '°C', ph: 'pH', turbidity: 'NTU', tds: 'ppm' }[parameter];
  return {
    parameter, unit, observed: { value: 27, observed_at: '2026-10-13T12:00:00Z' },
    warning_bounds: { min: 24, max: 28 }, critical_bounds: { min: 22, max: 31 },
    trend: { status: 'rising', reason: null, rate_per_hour: .18, rate_ci_low: .12, rate_ci_high: .24,
      change_6h: 1.08, notable_change: .5, qualifying_buckets: 12, required_buckets: 10,
      fit_points: [{ t: '2026-10-13T06:15:00Z', value: 26, count: 60 }, { t: '2026-10-13T11:45:00Z', value: 27, count: 60 }],
      fitted_start: { t: '2026-10-13T06:15:00Z', value: 26 }, fitted_end: { t: '2026-10-13T12:00:00Z', value: 27 }, sigma: .05 },
    headroom: { side: 'upper', bound: 28, distance: 1, outside: false, reason: null },
    species_range: { status: 'ok', min: 24, max: 28, species_count: 2, conflict: null, compliance_percent_24h: 91.5,
      headroom: null, compliance_reason: null, compliance_readings: 60, required_readings: 30 },
    projection: { status: parameter === 'turbidity' ? 'not_applicable' : 'crossing_projected', reason: null,
      bound_side: 'upper', bound: 28, crossing_hours_low: 1.9, crossing_hours_high: 2.7, horizon_hours: 3,
      band: parameter === 'turbidity' ? [] : [{ t: '2026-10-13T12:00:00Z', low: 26.8, mid: 27, high: 27.2 },
        { t: '2026-10-13T15:00:00Z', low: 27.5, mid: 28, high: 28.5 }] },
    stability: { status: 'typical', reason: null, current_spread: .04, baseline_spread: .035, ratio: 1.14, current_buckets: 48, baseline_days_covered: 7 },
  };
}
export function tankFixture(id = 1): CurrentTankInsights {
  return { tank_id: id, tank_name: `Tank ${id}`, latest: { observed_at: '2026-10-13T12:00:00Z', received_at: '2026-10-13T12:00:00Z', is_current: true },
    parameters: (['temperature', 'ph', 'turbidity', 'tds'] as const).map(parameterFixture) };
}
export function insightsFixture(): CurrentInsightsResponse {
  return { evaluated_at: '2026-10-13T12:05:00Z', method_version: 'ci-v1',
    constants: { fit_hours: 6, horizon_hours: 3, baseline_days: 7, bucket_minutes: 30 },
    tanks: [tankFixture(1), tankFixture(2)], attention: [{ tank_id: 2, tank_name: 'Tank 2', parameter: 'temperature',
      kind: 'projected', type: 'crossing_projected', crossing_hours_low: 1.9, crossing_hours_high: 2.7, ratio: null }] };
}

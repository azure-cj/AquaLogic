import type { CurrentHeadroom, CurrentProjection, CurrentSpeciesRange, CurrentStability, CurrentTrend } from '../types';

export const formatRate = (value: number) => Math.abs(value).toFixed(2);
export const formatNumber = (value: number) => String(Number(value.toFixed(2)));
export function trendCopy(trend: CurrentTrend, unit: string): string {
  switch (trend.status) {
    case 'rising': case 'falling':
      return `${trend.status === 'rising' ? 'Rising' : 'Falling'} ${trend.rate_per_hour == null ? '—' : formatRate(trend.rate_per_hour)} ${unit}/h over the last 6 h`;
    case 'steady': return 'Steady over the last 6 h';
    case 'uncertain': return 'No clear direction — readings vary';
    case 'insufficient_data':
      switch (trend.reason) {
        case 'gap': return 'Recent readings have a gap over 1 hour';
        case 'not_recent': return 'No readings in the last half hour';
        case 'mixed_source': return 'Readings come from more than one source';
        default: return `Not enough recent readings (${trend.qualifying_buckets} of ${trend.required_buckets} half-hour intervals)`;
      }
  }
}
export function headroomCopy(headroom: CurrentHeadroom | null, unit: string): string {
  if (!headroom) return 'Warning thresholds disabled';
  if (headroom.outside) return 'Outside the warning range';
  if (headroom.reason === 'side_bound_missing' || headroom.bound == null) return 'No warning bound configured on this side';
  if (headroom.distance == null) return 'No observed value to assess warning headroom';
  return `${formatNumber(headroom.distance)} ${unit} from the ${headroom.side} warning bound (${formatNumber(headroom.bound)} ${unit})`;
}
export function crossingTimeCopy(low: number | null, high: number | null): string {
  if (low == null) return 'at an unavailable time';
  const lo = Math.round(low * 2) / 2;
  const hi = high == null ? null : Math.round(high * 2) / 2;
  if (hi == null) return `in about ${lo} h or later`;
  if (lo === 0) return hi === 0 ? 'soon; the latest readings are close to the bound' : `within about ${hi} h`;
  if (lo === hi) return `in about ${lo} h`;
  return `in about ${lo}–${hi} h`;
}
export function projectionCopy(projection: CurrentProjection, unit: string): string {
  switch (projection.status) {
    case 'crossing_projected': return `If the current trend continues, may reach the ${projection.bound_side} warning bound (${projection.bound == null ? '—' : formatNumber(projection.bound)} ${unit}) ${crossingTimeCopy(projection.crossing_hours_low, projection.crossing_hours_high)}`;
    case 'no_crossing_within_horizon': return 'Not projected to reach a warning bound within 3 h if the trend continues';
    case 'too_uncertain': return 'Trend too uncertain to project';
    case 'stale': return 'No projection: the latest reading is not current';
    case 'insufficient_data': return 'No projection: not enough recent readings';
    case 'already_outside': return 'Already outside the warning range — see alerts';
    case 'no_bound': return 'No warning bound configured on this side';
    case 'not_applicable': return 'Turbidity is not projected because it changes in sudden events';
  }
}
export function stabilityCopy(stability: CurrentStability): string {
  switch (stability.status) {
    case 'more_variable': return `More variable than usual (${stability.ratio?.toFixed(1) ?? '—'}× its 7-day baseline)`;
    case 'steadier': return `Steadier than usual (${stability.ratio?.toFixed(1) ?? '—'}× its 7-day baseline)`;
    case 'typical': return 'Typical variability for this tank';
    case 'insufficient_data': return 'Not enough readings in the last 24 h';
    case 'insufficient_baseline': return `Baseline needs 5 days of readings (${stability.baseline_days_covered} available)`;
  }
}
export function speciesCopy(species: CurrentSpeciesRange, unit: string): string {
  switch (species.status) {
    case 'ok': {
      const range = `${species.min == null ? 'unbounded' : formatNumber(species.min)}–${species.max == null ? 'unbounded' : formatNumber(species.max)} ${unit}`;
      if (species.compliance_percent_24h == null) return species.compliance_reason === 'mixed_source'
        ? `Assigned species' range (${range}); readings come from more than one source`
        : `Assigned species' range (${range}); not enough readings to assess the last 24 h (${species.compliance_readings} of ${species.required_readings})`;
      return `${formatNumber(species.compliance_percent_24h)}% of the last 24 h within the assigned species' range (${range})`;
    }
    case 'conflict': return species.conflict
      ? `Assigned species' ranges do not overlap: ${species.conflict.min_species} needs at least ${formatNumber(species.conflict.min)}, ${species.conflict.max_species} needs at most ${formatNumber(species.conflict.max)}`
      : "Assigned species' ranges do not overlap";
    case 'not_configured': return 'No species range configured';
    case 'not_applicable': return 'Turbidity has no species range';
  }
}

export type AnalyticsRange = '24h' | '7d' | '30d' | 'custom';
export type AnalyticsBucket = 'auto' | '15m' | '1h' | '6h' | '1d';

export type MetricKey =
  | 'temperature'
  | 'ph'
  | 'turbidity'
  | 'dissolved_oxygen'
  | 'tds'
  | 'ammonia';

// Ammonia and dissolved oxygen remain in the API/data contract, but are
// intentionally excluded from the current web release because their scope is
// deferred.
export const metricOptions = [
  { key: 'temperature', label: 'Temperature', unit: '°C', color: '#0e9f97' },
  { key: 'ph', label: 'pH', unit: 'pH', color: '#4169a1' },
  { key: 'turbidity', label: 'Turbidity', unit: 'NTU', color: '#8a6a3d' },
  { key: 'tds', label: 'TDS', unit: 'ppm', color: '#7659a5' },
] as const satisfies ReadonlyArray<{ key: MetricKey; label: string; unit: string; color: string }>;
export type MetricValues = Record<MetricKey, number | null>;

export type AnalyticsPoint = {
  timestamp: string;
  values: MetricValues;
  sample_count: number;
  contributor_count: number;
};

export type TankSeries = {
  tank_id: number;
  tank_name: string;
  series: AnalyticsPoint[];
};

export type MetricStats = {
  average: number | null;
  minimum: number | null;
  maximum: number | null;
  previous_average: number | null;
  absolute_change: number | null;
  percent_change: number | null;
};

export type AnalyticsAlert = {
  id: number;
  tank_id: number;
  tank_name: string;
  reading_id: number | null;
  parameter: MetricKey;
  severity: 'warning' | 'critical';
  message: string;
  timestamp: string;
  value: number | null;
};

export type ThresholdSegment = {
  parameter: MetricKey;
  unit: string;
  start: string;
  end: string;
  warning_min: number | null;
  warning_max: number | null;
  critical_min: number | null;
  critical_max: number | null;
  enabled: boolean;
  source?: 'global' | 'tank_override' | 'shared';
  tank_id?: number | null;
};

export type TankUptime = {
  tank_id: number;
  tank_name: string;
  uptime: number;
  previous_uptime: number;
  reported_intervals: number;
  previous_reported_intervals: number;
  expected_intervals: number;
  status: 'healthy' | 'degraded' | 'critical' | 'no_data';
};

export type AnalyticsResponse = {
  decision_support_insights?: {
    cards: DecisionSupportCard[];
    limitations: Array<{ tank_id: number; tank_name: string; parameter: string; rule: string; reason: string; samples: number; interval_coverage?: number; excluded?: number }>;
    advisory: string;
  } | null;
  window: {
    range: AnalyticsRange;
    start: string;
    end: string;
    bucket_seconds: number;
    water_quality_bucket_seconds: number;
    timezone: string;
  };
  tanks: Array<{ id: number; name: string; lifecycle: 'active' | 'retired'; }>;
  fleet_series: AnalyticsPoint[];
  previous_fleet_series: AnalyticsPoint[];
  tank_series: TankSeries[];
  stats: Record<MetricKey, MetricStats>;
  alert_counts: { warning: number; critical: number; };
  alert_series: Array<{ timestamp: string; warning: number; critical: number; }>;
  alert_events: AnalyticsAlert[];
  threshold_segments: ThresholdSegment[];
  threshold_scope?: 'shared' | 'tank' | 'varies';
  threshold_tank_id?: number | null;
  thresholds_vary_by_tank?: boolean;
  uptime: TankUptime[];
  uptime_comparison: {
    current: number;
    previous: number;
    change: number;
  };
  uptime_thresholds: { healthy: number; degraded: number; };
  insights: {
    alert_count: number;
    reporting_gap_count: number;
    lowest_uptime_tank_id: number | null;
    primary_driver_by_metric: Record<MetricKey, number | null>;
  };
};

export type DecisionSupportCard = {
  id: string; rule: 'within_range' | 'repeated_alerts' | 'increasing' | 'decreasing' | 'little_change';
  parameter: MetricKey; scope: 'tank'; tank_id: number; tank_name: string;
  title: string; explanation: string; window_start: string; window_end: string;
  observation_start: string | null; observation_end: string | null; samples: number; unit: string;
  evidence: Record<string, number | string>; qualifications: string[]; checks: string[]; related_alert_ids: number[];
};

export type CurrentParameter = 'temperature' | 'ph' | 'turbidity' | 'tds';
export type CurrentInsightPoint = { t: string; value: number };
export type CurrentFitPoint = CurrentInsightPoint & { count: number };
export type CurrentBounds = { min: number | null; max: number | null };
export type CurrentTrend = {
  status: 'rising' | 'falling' | 'steady' | 'uncertain' | 'insufficient_data';
  reason: 'too_few_buckets' | 'gap' | 'not_recent' | 'mixed_source' | null;
  rate_per_hour: number | null; rate_ci_low: number | null; rate_ci_high: number | null;
  change_6h: number | null; notable_change: number | null;
  qualifying_buckets: number; required_buckets: number;
  fit_points: CurrentFitPoint[]; fitted_start: CurrentInsightPoint | null;
  fitted_end: CurrentInsightPoint | null; sigma: number | null;
};
export type CurrentHeadroom = {
  side: 'upper' | 'lower'; bound: number | null; distance: number | null;
  outside: boolean | null; reason: 'side_bound_missing' | 'value_unavailable' | null;
};
export type SpeciesRangeConflict = { min_species: string; min: number; max_species: string; max: number };
export type CurrentSpeciesRange = CurrentBounds & {
  status: 'ok' | 'conflict' | 'not_configured' | 'not_applicable';
  species_count: number; conflict: SpeciesRangeConflict | null;
  compliance_percent_24h: number | null; headroom: CurrentHeadroom | null;
  compliance_reason: 'too_few_readings' | 'mixed_source' | null;
  compliance_readings: number; required_readings: number;
};
export type ProjectionBandPoint = { t: string; low: number; mid: number; high: number };
export type CurrentProjection = {
  status: 'crossing_projected' | 'no_crossing_within_horizon' | 'too_uncertain' | 'stale'
    | 'insufficient_data' | 'already_outside' | 'no_bound' | 'not_applicable';
  reason: string | null; bound_side: 'upper' | 'lower' | null; bound: number | null;
  crossing_hours_low: number | null; crossing_hours_high: number | null;
  horizon_hours: number; band: ProjectionBandPoint[];
};
export type CurrentStability = {
  status: 'more_variable' | 'typical' | 'steadier' | 'insufficient_data' | 'insufficient_baseline';
  reason: string | null; current_spread: number | null; baseline_spread: number | null;
  ratio: number | null; current_buckets: number; baseline_days_covered: number;
};
export type CurrentObserved = { value: number; observed_at: string };
export type CurrentParameterInsights = {
  parameter: CurrentParameter; unit: string; observed: CurrentObserved | null;
  warning_bounds: CurrentBounds | null; critical_bounds: CurrentBounds | null;
  trend: CurrentTrend; headroom: CurrentHeadroom | null; species_range: CurrentSpeciesRange;
  projection: CurrentProjection; stability: CurrentStability;
};
export type CurrentLatest = { observed_at: string | null; received_at: string | null; is_current: boolean };
export type CurrentTankInsights = { tank_id: number; tank_name: string; latest: CurrentLatest; parameters: CurrentParameterInsights[] };
export type CurrentAttentionItem = {
  tank_id: number; tank_name: string; parameter: CurrentParameter;
  kind: 'projected' | 'derived'; type: 'crossing_projected' | 'more_variable' | 'species_conflict';
  crossing_hours_low: number | null; crossing_hours_high: number | null; ratio: number | null;
};
export type CurrentInsightConstants = { fit_hours: number; horizon_hours: number; baseline_days: number; bucket_minutes: number };
export type CurrentInsightsResponse = {
  evaluated_at: string; method_version: string; constants: CurrentInsightConstants;
  tanks: CurrentTankInsights[]; attention: CurrentAttentionItem[];
};

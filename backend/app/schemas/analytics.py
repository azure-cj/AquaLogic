from datetime import datetime
from typing import Any, Dict, List, Literal, Optional

from pydantic import BaseModel


MetricValues = Dict[str, Optional[float]]


class AnalyticsWindow(BaseModel):
    range: str
    start: datetime
    end: datetime
    bucket_seconds: int
    water_quality_bucket_seconds: int
    timezone: str = "Asia/Manila"


class AnalyticsPoint(BaseModel):
    timestamp: datetime
    values: MetricValues
    sample_count: int
    contributor_count: int


class TankSeries(BaseModel):
    tank_id: int
    tank_name: str
    series: List[AnalyticsPoint]


class MetricStats(BaseModel):
    average: Optional[float]
    minimum: Optional[float]
    maximum: Optional[float]
    previous_average: Optional[float]
    absolute_change: Optional[float]
    percent_change: Optional[float]


class AlertBucket(BaseModel):
    timestamp: datetime
    warning: int
    critical: int


class AnalyticsAlert(BaseModel):
    id: int
    tank_id: int
    tank_name: str
    reading_id: Optional[int]
    parameter: str
    severity: Literal["warning", "critical"]
    message: str
    timestamp: datetime
    value: Optional[float]


class ThresholdSegment(BaseModel):
    parameter: str
    unit: str
    start: datetime
    end: datetime
    warning_min: Optional[float]
    warning_max: Optional[float]
    critical_min: Optional[float]
    critical_max: Optional[float]
    enabled: bool
    source: Literal["global", "tank_override", "shared"]
    tank_id: Optional[int] = None


class TankOption(BaseModel):
    id: int
    name: str
    lifecycle: Literal["active", "retired"] = "active"


class TankUptime(BaseModel):
    tank_id: int
    tank_name: str
    uptime: float
    previous_uptime: float
    reported_intervals: int
    previous_reported_intervals: int
    expected_intervals: int
    status: Literal["healthy", "degraded", "critical", "no_data"]


class UptimeComparison(BaseModel):
    current: float
    previous: float
    change: float


class UptimeThresholds(BaseModel):
    healthy: float
    degraded: float


class AnalyticsInsights(BaseModel):
    alert_count: int
    reporting_gap_count: int
    lowest_uptime_tank_id: Optional[int]
    primary_driver_by_metric: Dict[str, Optional[int]]


class DecisionSupportCard(BaseModel):
    id: str
    rule: Literal["within_range", "repeated_alerts", "increasing", "decreasing", "little_change"]
    parameter: Literal["temperature", "ph", "turbidity", "tds"]
    scope: Literal["tank"]
    tank_id: int
    tank_name: str
    title: str
    explanation: str
    window_start: datetime
    window_end: datetime
    observation_start: datetime | None
    observation_end: datetime | None
    samples: int
    unit: str
    evidence: dict[str, Any]
    qualifications: list[str]
    checks: list[str]
    related_alert_ids: list[int]


class DecisionSupportInsights(BaseModel):
    cards: list[DecisionSupportCard]
    limitations: list[dict[str, Any]]
    advisory: str


class AnalyticsResponse(BaseModel):
    window: AnalyticsWindow
    tanks: List[TankOption]
    fleet_series: List[AnalyticsPoint]
    previous_fleet_series: List[AnalyticsPoint]
    tank_series: List[TankSeries]
    stats: Dict[str, MetricStats]
    alert_counts: Dict[str, int]
    alert_series: List[AlertBucket]
    alert_events: List[AnalyticsAlert]
    threshold_segments: List[ThresholdSegment]
    threshold_scope: Literal["shared", "tank", "varies"]
    threshold_tank_id: Optional[int] = None
    thresholds_vary_by_tank: bool = False
    uptime: List[TankUptime]
    uptime_comparison: UptimeComparison
    uptime_thresholds: UptimeThresholds
    insights: AnalyticsInsights
    decision_support_insights: DecisionSupportInsights | None = None


class CurrentInsightConstants(BaseModel):
    fit_hours: float
    horizon_hours: float
    baseline_days: int
    bucket_minutes: float


class CurrentInsightPoint(BaseModel):
    t: datetime
    value: float


class CurrentFitPoint(CurrentInsightPoint):
    count: int


class CurrentTrend(BaseModel):
    status: Literal['rising', 'falling', 'steady', 'uncertain', 'insufficient_data']
    reason: Literal['too_few_buckets', 'gap', 'not_recent', 'mixed_source'] | None
    rate_per_hour: float | None
    rate_ci_low: float | None
    rate_ci_high: float | None
    change_6h: float | None
    notable_change: float | None
    qualifying_buckets: int
    required_buckets: int
    fit_points: list[CurrentFitPoint]
    fitted_start: CurrentInsightPoint | None
    fitted_end: CurrentInsightPoint | None
    sigma: float | None


class CurrentBounds(BaseModel):
    min: float | None
    max: float | None


class CurrentHeadroom(BaseModel):
    side: Literal['upper', 'lower']
    bound: float | None
    distance: float | None
    outside: bool | None
    reason: Literal['side_bound_missing', 'value_unavailable'] | None = None


class SpeciesRangeConflict(BaseModel):
    min_species: str
    min: float
    max_species: str
    max: float


class CurrentSpeciesRange(CurrentBounds):
    status: Literal['ok', 'conflict', 'not_configured', 'not_applicable']
    species_count: int
    conflict: SpeciesRangeConflict | None
    compliance_percent_24h: float | None
    headroom: CurrentHeadroom | None
    compliance_reason: Literal['too_few_readings', 'mixed_source'] | None
    compliance_readings: int
    required_readings: int


class ProjectionBandPoint(BaseModel):
    t: datetime
    low: float
    mid: float
    high: float


class CurrentProjection(BaseModel):
    status: Literal['crossing_projected', 'no_crossing_within_horizon', 'too_uncertain', 'stale',
                    'insufficient_data', 'already_outside', 'no_bound', 'not_applicable']
    reason: str | None
    bound_side: Literal['upper', 'lower'] | None
    bound: float | None
    crossing_hours_low: float | None
    crossing_hours_high: float | None
    horizon_hours: float
    band: list[ProjectionBandPoint]


class CurrentStability(BaseModel):
    status: Literal['more_variable', 'typical', 'steadier', 'insufficient_data', 'insufficient_baseline']
    reason: str | None
    current_spread: float | None
    baseline_spread: float | None
    ratio: float | None
    current_buckets: int
    baseline_days_covered: int


class CurrentObserved(BaseModel):
    value: float
    observed_at: datetime


class CurrentParameterInsights(BaseModel):
    parameter: Literal['temperature', 'ph', 'turbidity', 'tds']
    unit: str
    observed: CurrentObserved | None
    warning_bounds: CurrentBounds | None
    critical_bounds: CurrentBounds | None
    trend: CurrentTrend
    headroom: CurrentHeadroom | None
    species_range: CurrentSpeciesRange
    projection: CurrentProjection
    stability: CurrentStability


class CurrentLatest(BaseModel):
    observed_at: datetime | None
    received_at: datetime | None
    is_current: bool


class CurrentTankInsights(BaseModel):
    tank_id: int
    tank_name: str
    latest: CurrentLatest
    parameters: list[CurrentParameterInsights]


class CurrentAttentionItem(BaseModel):
    tank_id: int
    tank_name: str
    parameter: Literal['temperature', 'ph', 'turbidity', 'tds']
    kind: Literal['projected', 'derived']
    type: Literal['crossing_projected', 'more_variable', 'species_conflict']
    crossing_hours_low: float | None
    crossing_hours_high: float | None
    ratio: float | None


class CurrentInsightsResponse(BaseModel):
    evaluated_at: datetime
    method_version: str
    constants: CurrentInsightConstants
    tanks: list[CurrentTankInsights]
    attention: list[CurrentAttentionItem]

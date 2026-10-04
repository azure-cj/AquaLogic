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

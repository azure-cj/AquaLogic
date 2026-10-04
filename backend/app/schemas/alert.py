from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, field_validator

from app.models import AlertSeverity
from .sensor import make_timestamp_explicit_utc


class AlertRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    tank_id: int
    reading_id: int | None
    parameter: str
    severity: AlertSeverity
    message: str
    is_resolved: bool
    resolved_at: datetime | None = None
    resolved_by_user_id: int | None = None
    resolution_source: Literal["operator", "system"] | None = None
    created_at: datetime

    @field_validator("created_at", "resolved_at", mode="after")
    @classmethod
    def normalize_timestamps(cls, value: datetime | None) -> datetime | None:
        return make_timestamp_explicit_utc(value)


class AlertContextTank(BaseModel):
    id: int
    display_name: str
    lifecycle: Literal["active", "retired"]


class AlertContextReading(BaseModel):
    reading_id: int
    value: float | None
    unit: str
    observed_at: datetime
    received_at: datetime
    reporting_freshness: Literal["fresh", "stale"]


class AlertContextThreshold(BaseModel):
    parameter: str
    unit: str
    warning_min: float | None
    warning_max: float | None
    critical_min: float | None
    critical_max: float | None
    enabled: bool
    source: Literal["tank", "global"]
    updated_at: datetime | None

    @field_validator("updated_at", mode="after")
    @classmethod
    def normalize_timestamp(cls, value: datetime | None) -> datetime | None:
        return make_timestamp_explicit_utc(value)


class OperatorGuidance(BaseModel):
    code: str
    direction: Literal["above", "below", "unavailable"]
    explanation: str
    checks: list[str]
    advisory: str


class SpeciesContextReading(BaseModel):
    reading_id: int
    observed_at: datetime
    received_at: datetime


class SpeciesContextRow(BaseModel):
    species_id: int
    name: str
    stored_min: float | None
    stored_max: float | None
    result: Literal["within", "outside", "unavailable"]
    reason: str


class SpeciesContext(BaseModel):
    parameter: str
    basis: Literal["current_assignments_latest_reading"]
    status: Literal["available", "unavailable", "unsupported"]
    reason: str | None
    reading: SpeciesContextReading | None
    counts: dict[str, int]
    species: list[SpeciesContextRow]
    unit: str
    advisory: str


class AlertContextRead(BaseModel):
    alert: AlertRead
    tank: AlertContextTank
    evaluated_at: datetime
    linked_reading: AlertContextReading | None
    linked_threshold: AlertContextThreshold | None
    latest_reading: AlertContextReading | None
    current_threshold: AlertContextThreshold | None
    guidance: OperatorGuidance
    species_context: SpeciesContext | None = None

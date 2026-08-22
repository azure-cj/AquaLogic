from datetime import datetime, timezone
from typing import Literal

from pydantic import BaseModel, Field, field_validator


def _utc(value: datetime | None) -> datetime | None:
    if value is None:
        return None
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


class MonitoringIncidentRead(BaseModel):
    id: int
    tank_id: int
    tank_name: str
    tank_lifecycle: Literal["active", "retired"]
    state: Literal["active", "resolved"]
    started_at: datetime
    detected_at: datetime
    last_reading_received_at: datetime | None = None
    last_report_age_seconds: int | None = None
    resolved_at: datetime | None = None
    resolution_reason: Literal["reporting_recovered", "monitoring_disabled", "tank_retired"] | None = None
    recovery_reading_id: int | None = None
    duration_seconds: int = Field(ge=0)

    @field_validator("started_at", "detected_at", "last_reading_received_at", "resolved_at", mode="after")
    @classmethod
    def normalize_timestamps(cls, value: datetime | None) -> datetime | None:
        return _utc(value)


class MonitoringIncidentPage(BaseModel):
    items: list[MonitoringIncidentRead]
    page: int
    page_size: int
    total: int
    total_pages: int
    has_previous: bool
    has_next: bool

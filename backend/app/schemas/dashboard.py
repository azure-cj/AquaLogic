from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, field_validator

from .sensor import SensorReadingRead, make_timestamp_explicit_utc


class CustomerSummary(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    name: str


class FleetTankRead(BaseModel):
    id: int
    public_id: str
    name: str
    location: str
    customer: CustomerSummary | None = None
    latest_reading: SensorReadingRead | None = None
    status: Literal["normal", "warning", "critical", "offline"]
    last_reading_at: datetime | None = None
    reporting_age_seconds: int | None = None
    active_warning_count: int
    active_critical_count: int
    species_care_status: Literal["suitable", "attention", "unavailable"]
    assigned_species_count: int

    @field_validator("last_reading_at", mode="after")
    @classmethod
    def normalize_last_reading(cls, value: datetime | None) -> datetime | None:
        return make_timestamp_explicit_utc(value)

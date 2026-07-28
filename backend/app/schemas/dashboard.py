from datetime import datetime
from typing import Literal

from pydantic import BaseModel, validator

from .sensor import SensorReadingRead, make_timestamp_explicit_utc


class CustomerSummary(BaseModel):
    id: int
    name: str

    class Config:
        orm_mode = True


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

    _make_last_reading_explicit_utc = validator("last_reading_at", allow_reuse=True)(
        make_timestamp_explicit_utc
    )

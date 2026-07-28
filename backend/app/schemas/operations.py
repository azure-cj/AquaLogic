from datetime import datetime
from typing import Literal

from pydantic import BaseModel, field_validator

from .alert import AlertRead
from .sensor import SensorReadingRead, make_timestamp_explicit_utc


class TankOperationsResponse(BaseModel):
    tank_id: int
    evaluated_at: datetime
    status: Literal["normal", "warning", "critical", "offline"]
    latest_reading: SensorReadingRead | None = None
    parameter_statuses: dict[str, str]
    active_alerts: list[AlertRead]

    @field_validator("evaluated_at", mode="after")
    @classmethod
    def normalize_evaluated_at(cls, value: datetime) -> datetime:
        return make_timestamp_explicit_utc(value)  # type: ignore[return-value]

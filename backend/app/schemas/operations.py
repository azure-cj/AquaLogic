from datetime import datetime
from typing import Literal

from pydantic import BaseModel, validator

from .alert import AlertRead
from .sensor import SensorReadingRead, make_timestamp_explicit_utc


class TankOperationsResponse(BaseModel):
    tank_id: int
    evaluated_at: datetime
    status: Literal["normal", "warning", "critical", "offline"]
    latest_reading: SensorReadingRead | None = None
    parameter_statuses: dict[str, str]
    active_alerts: list[AlertRead]

    _make_evaluated_explicit_utc = validator("evaluated_at", allow_reuse=True)(
        make_timestamp_explicit_utc
    )

from datetime import datetime

from pydantic import BaseModel, validator

from app.models import AlertSeverity
from .sensor import make_timestamp_explicit_utc


class AlertRead(BaseModel):
    id: int
    tank_id: int
    reading_id: int | None
    parameter: str
    severity: AlertSeverity
    message: str
    is_resolved: bool
    resolved_at: datetime | None = None
    resolved_by_user_id: int | None = None
    created_at: datetime

    _make_created_explicit_utc = validator("created_at", allow_reuse=True)(
        make_timestamp_explicit_utc
    )
    _make_resolved_explicit_utc = validator("resolved_at", allow_reuse=True)(
        make_timestamp_explicit_utc
    )

    class Config:
        orm_mode = True

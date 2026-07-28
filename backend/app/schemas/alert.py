from datetime import datetime

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
    created_at: datetime

    @field_validator("created_at", "resolved_at", mode="after")
    @classmethod
    def normalize_timestamps(cls, value: datetime | None) -> datetime | None:
        return make_timestamp_explicit_utc(value)

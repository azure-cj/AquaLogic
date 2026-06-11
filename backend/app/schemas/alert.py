from datetime import datetime

from pydantic import BaseModel

from app.models import AlertSeverity


class AlertRead(BaseModel):
    id: int
    tank_id: int
    reading_id: int | None
    parameter: str
    severity: AlertSeverity
    message: str
    is_resolved: bool
    created_at: datetime

    class Config:
        orm_mode = True

from datetime import datetime, timezone

from pydantic import BaseModel, validator


def make_timestamp_explicit_utc(value: datetime | None) -> datetime | None:
    """Normalize SQLite's timezone-less timestamps for API responses."""
    if value is None:
        return None
    return value.replace(tzinfo=timezone.utc) if value.tzinfo is None else value


class SensorReadingBase(BaseModel):
    temperature: float
    ph: float
    turbidity: float
    dissolved_oxygen: float
    tds: float
    ammonia: float
    is_mock: bool = False


class SensorReadingCreate(SensorReadingBase):
    timestamp: datetime | None = None


class SensorReadingRead(SensorReadingBase):
    id: int
    tank_id: int
    timestamp: datetime

    _make_timestamp_explicit_utc = validator("timestamp", allow_reuse=True)(
        make_timestamp_explicit_utc
    )

    class Config:
        orm_mode = True


class SensorReadingPublic(BaseModel):
    timestamp: datetime
    temperature: float
    ph: float
    turbidity: float
    dissolved_oxygen: float
    tds: float
    ammonia: float

    @validator("timestamp")
    def make_timestamp_explicit_utc(cls, value: datetime) -> datetime:
        # SQLite returns naive datetimes even for timezone-aware columns.
        # Public clients need an offset so relative time is not shifted by the
        # visitor's local timezone.
        return make_timestamp_explicit_utc(value)

    class Config:
        orm_mode = True

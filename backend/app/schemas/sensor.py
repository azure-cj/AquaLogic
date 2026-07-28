from datetime import datetime, timezone

from pydantic import BaseModel, ConfigDict, field_validator


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
    model_config = ConfigDict(from_attributes=True)

    id: int
    tank_id: int
    timestamp: datetime

    @field_validator("timestamp", mode="after")
    @classmethod
    def _make_timestamp_explicit_utc(cls, value: datetime) -> datetime:
        return make_timestamp_explicit_utc(value)  # type: ignore[return-value]


class SensorReadingPublic(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    timestamp: datetime
    temperature: float
    ph: float
    turbidity: float
    dissolved_oxygen: float
    tds: float
    ammonia: float

    @field_validator("timestamp", mode="after")
    @classmethod
    def round_timestamp_to_minute(cls, value: datetime) -> datetime:
        value = make_timestamp_explicit_utc(value)
        return value.replace(second=0, microsecond=0)  # type: ignore[union-attr]

    @field_validator("temperature", "ph", "turbidity", "dissolved_oxygen", mode="after")
    @classmethod
    def round_one_decimal(cls, value: float) -> float:
        return round(value, 1)

    @field_validator("tds", mode="after")
    @classmethod
    def round_tds(cls, value: float) -> float:
        return round(value)

    @field_validator("ammonia", mode="after")
    @classmethod
    def round_ammonia(cls, value: float) -> float:
        return round(value, 2)

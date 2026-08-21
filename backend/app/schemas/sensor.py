from datetime import datetime, timezone

from pydantic import BaseModel, ConfigDict, Field, field_validator


TEMPERATURE_MIN = -10
TEMPERATURE_MAX = 60
PH_MIN = 0
PH_MAX = 14
TURBIDITY_MIN = 0
TURBIDITY_MAX = 3000
TDS_MIN = 0
TDS_MAX = 5000


def make_timestamp_explicit_utc(value: datetime | None) -> datetime | None:
    """Normalize SQLite's timezone-less timestamps for API responses."""
    if value is None:
        return None
    normalized = value.replace(tzinfo=timezone.utc) if value.tzinfo is None else value
    return normalized.astimezone(timezone.utc)


class SensorReadingBase(BaseModel):
    temperature: float = Field(ge=TEMPERATURE_MIN, le=TEMPERATURE_MAX, allow_inf_nan=False)
    ph: float = Field(ge=PH_MIN, le=PH_MAX, allow_inf_nan=False)
    turbidity: float = Field(ge=TURBIDITY_MIN, le=TURBIDITY_MAX, allow_inf_nan=False)
    dissolved_oxygen: float | None = None
    tds: float = Field(ge=TDS_MIN, le=TDS_MAX, allow_inf_nan=False)
    ammonia: float | None = None
    is_mock: bool = False


class SensorReadingCreate(SensorReadingBase):
    model_config = ConfigDict(extra="forbid")

    timestamp: datetime | None = None

    @field_validator("timestamp", mode="after")
    @classmethod
    def _normalize_timestamp_utc(cls, value: datetime | None) -> datetime | None:
        return make_timestamp_explicit_utc(value)


class SensorReadingRead(SensorReadingBase):
    model_config = ConfigDict(from_attributes=True)

    id: int
    device_id: str | None = None
    tank_id: int
    timestamp: datetime
    received_at: datetime

    @field_validator("timestamp", mode="after")
    @classmethod
    def _make_timestamp_explicit_utc(cls, value: datetime) -> datetime:
        return make_timestamp_explicit_utc(value)  # type: ignore[return-value]

    @field_validator("received_at", mode="after")
    @classmethod
    def _make_received_at_explicit_utc(cls, value: datetime) -> datetime:
        return make_timestamp_explicit_utc(value)  # type: ignore[return-value]


class SensorReadingPublic(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    timestamp: datetime
    temperature: float
    ph: float
    turbidity: float
    dissolved_oxygen: float | None = None
    tds: float
    ammonia: float | None = None

    @field_validator("timestamp", mode="after")
    @classmethod
    def round_timestamp_to_minute(cls, value: datetime) -> datetime:
        value = make_timestamp_explicit_utc(value)
        return value.replace(second=0, microsecond=0)  # type: ignore[union-attr]

    @field_validator("temperature", "ph", "turbidity", "dissolved_oxygen", mode="after")
    @classmethod
    def round_one_decimal(cls, value: float | None) -> float | None:
        return round(value, 1) if value is not None else None

    @field_validator("tds", mode="after")
    @classmethod
    def round_tds(cls, value: float) -> float:
        return round(value)

    @field_validator("ammonia", mode="after")
    @classmethod
    def round_ammonia(cls, value: float | None) -> float | None:
        return round(value, 2) if value is not None else None


class DeviceReadingCreate(BaseModel):
    """The v1 bridge payload deliberately contains only installed sensors."""

    model_config = ConfigDict(extra="forbid")

    observed_at: datetime | None = None
    temperature: float = Field(ge=TEMPERATURE_MIN, le=TEMPERATURE_MAX, allow_inf_nan=False)
    ph: float = Field(ge=PH_MIN, le=PH_MAX, allow_inf_nan=False)
    turbidity: float = Field(ge=TURBIDITY_MIN, le=TURBIDITY_MAX, allow_inf_nan=False)
    tds: float = Field(ge=TDS_MIN, le=TDS_MAX, allow_inf_nan=False)

    @field_validator("observed_at", mode="after")
    @classmethod
    def _normalize_observed_at_utc(cls, value: datetime | None) -> datetime | None:
        return make_timestamp_explicit_utc(value)

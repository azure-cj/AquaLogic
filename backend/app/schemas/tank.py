from datetime import date, datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator
from urllib.parse import urlparse

from app.config import settings

from .fish import FishSpeciesRead
from .sensor import SensorReadingPublic
from .dashboard import CustomerSummary


class TankBase(BaseModel):
    name: str = Field(min_length=1, max_length=100)
    location: str = Field(min_length=1, max_length=150)
    public_location: str | None = Field(default=None, max_length=150)
    description: str | None = Field(default=None, max_length=10_000)
    is_public: bool = True
    customer_id: int | None = None
    feeding_schedule: str | None = Field(default=None, max_length=10_000)
    public_care_notes: str | None = Field(default=None, max_length=10_000)
    tank_code: str | None = Field(default=None, max_length=32)
    habitat_label: str | None = Field(default=None, max_length=80)
    water_type: Literal["freshwater", "saltwater", "brackish"] | None = None
    volume_liters: int | None = Field(default=None, gt=0)
    established_on: date | None = None
    hero_image_url: str | None = Field(default=None, max_length=500)

    @field_validator("hero_image_url")
    @classmethod
    def validate_public_image_url(cls, value: str | None) -> str | None:
        if value is None:
            return value
        parsed = urlparse(value)
        if parsed.scheme != "https" or not parsed.hostname or parsed.hostname not in settings.public_image_hosts:
            raise ValueError("Hero images must use HTTPS and an allowed image host")
        return value


class TankCreate(TankBase):
    pass


class TankUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=100)
    location: str | None = Field(default=None, min_length=1, max_length=150)
    public_location: str | None = Field(default=None, max_length=150)
    description: str | None = Field(default=None, max_length=10_000)
    is_public: bool | None = None
    customer_id: int | None = None
    feeding_schedule: str | None = Field(default=None, max_length=10_000)
    public_care_notes: str | None = Field(default=None, max_length=10_000)
    tank_code: str | None = Field(default=None, max_length=32)
    habitat_label: str | None = Field(default=None, max_length=80)
    water_type: Literal["freshwater", "saltwater", "brackish"] | None = None
    volume_liters: int | None = Field(default=None, gt=0)
    established_on: date | None = None
    hero_image_url: str | None = Field(default=None, max_length=500)

    @field_validator("hero_image_url")
    @classmethod
    def validate_public_image_url(cls, value: str | None) -> str | None:
        return TankBase.validate_public_image_url(value)


class TankRead(TankBase):
    id: int
    public_id: str
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


class TankDetail(TankRead):
    fish_species: list[FishSpeciesRead] = Field(default_factory=list)
    customer: CustomerSummary | None = None


class TankPublicRead(BaseModel):
    public_id: str
    name: str
    display_location: str | None = None
    description: str | None = None
    habitat_label: str | None = None
    water_type: Literal["freshwater", "saltwater", "brackish"] | None = None
    volume_liters: int | None = None
    established_on: date | None = None
    hero_image_url: str | None = None
    fish_species: list[FishSpeciesRead] = Field(default_factory=list)
    latest_reading: SensorReadingPublic | None = None
    status: str
    parameter_statuses: dict[str, str] = Field(default_factory=dict)
    public_care_notes: str | None = None

from datetime import date, datetime
from typing import Literal

from pydantic import BaseModel, Field

from .fish import FishSpeciesRead
from .sensor import SensorReadingPublic


class TankBase(BaseModel):
    name: str
    location: str
    description: str | None = None
    is_public: bool = True
    customer_id: int | None = None
    feeding_schedule: str | None = None
    public_care_notes: str | None = None
    tank_code: str | None = Field(default=None, max_length=32)
    habitat_label: str | None = Field(default=None, max_length=80)
    water_type: Literal["freshwater", "saltwater", "brackish"] | None = None
    volume_liters: int | None = Field(default=None, gt=0)
    established_on: date | None = None
    hero_image_url: str | None = Field(default=None, max_length=500)


class TankCreate(TankBase):
    pass


class TankUpdate(BaseModel):
    name: str | None = None
    location: str | None = None
    description: str | None = None
    is_public: bool | None = None
    customer_id: int | None = None
    feeding_schedule: str | None = None
    public_care_notes: str | None = None
    tank_code: str | None = Field(default=None, max_length=32)
    habitat_label: str | None = Field(default=None, max_length=80)
    water_type: Literal["freshwater", "saltwater", "brackish"] | None = None
    volume_liters: int | None = Field(default=None, gt=0)
    established_on: date | None = None
    hero_image_url: str | None = Field(default=None, max_length=500)


class TankRead(TankBase):
    id: int
    public_id: str
    created_at: datetime

    class Config:
        orm_mode = True


class TankDetail(TankRead):
    fish_species: list[FishSpeciesRead] = Field(default_factory=list)


class TankPublicRead(BaseModel):
    public_id: str
    name: str
    location: str
    description: str | None = None
    tank_code: str | None = None
    habitat_label: str | None = None
    water_type: Literal["freshwater", "saltwater", "brackish"] | None = None
    volume_liters: int | None = None
    established_on: date | None = None
    hero_image_url: str | None = None
    fish_species: list[FishSpeciesRead] = Field(default_factory=list)
    latest_reading: SensorReadingPublic | None = None
    status: str
    parameter_statuses: dict[str, str] = Field(default_factory=dict)
    feeding_schedule: str | None = None
    public_care_notes: str | None = None

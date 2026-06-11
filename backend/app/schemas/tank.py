from datetime import datetime

from pydantic import BaseModel, Field

from .fish import FishSpeciesRead
from .sensor import SensorReadingRead


class TankBase(BaseModel):
    name: str
    location: str
    description: str | None = None


class TankCreate(TankBase):
    pass


class TankUpdate(BaseModel):
    name: str | None = None
    location: str | None = None
    description: str | None = None


class TankRead(TankBase):
    id: int
    created_at: datetime

    class Config:
        orm_mode = True


class TankDetail(TankRead):
    fish_species: list[FishSpeciesRead] = Field(default_factory=list)


class TankPublicRead(BaseModel):
    id: int
    name: str
    location: str
    description: str | None = None
    fish_species: list[FishSpeciesRead] = Field(default_factory=list)
    latest_reading: SensorReadingRead | None = None

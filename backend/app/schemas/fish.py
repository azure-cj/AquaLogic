from datetime import datetime
from typing import Literal

from pydantic import BaseModel


class FishSpeciesBase(BaseModel):
    common_name: str
    scientific_name: str
    photo_url: str | None = None
    description: str | None = None
    category: str = "Other"
    ideal_temp_min: float | None = None
    ideal_temp_max: float | None = None
    ideal_ph_min: float | None = None
    ideal_ph_max: float | None = None
    ideal_do_min: float | None = None
    ideal_tds_min: float | None = None
    ideal_tds_max: float | None = None
    diet: str | None = None
    diet_type: Literal["Carnivore", "Omnivore", "Herbivore"] | None = None
    compatibility_notes: str | None = None
    care_tips: str | None = None


class FishSpeciesCreate(FishSpeciesBase):
    pass


class FishSpeciesUpdate(BaseModel):
    common_name: str | None = None
    scientific_name: str | None = None
    photo_url: str | None = None
    description: str | None = None
    category: str | None = None
    ideal_temp_min: float | None = None
    ideal_temp_max: float | None = None
    ideal_ph_min: float | None = None
    ideal_ph_max: float | None = None
    ideal_do_min: float | None = None
    ideal_tds_min: float | None = None
    ideal_tds_max: float | None = None
    diet: str | None = None
    diet_type: Literal["Carnivore", "Omnivore", "Herbivore"] | None = None
    compatibility_notes: str | None = None
    care_tips: str | None = None


class FishSpeciesRead(FishSpeciesBase):
    id: int
    created_at: datetime
    tank_count: int = 0

    class Config:
        orm_mode = True


class FishAssignmentRequest(BaseModel):
    fish_species_id: int

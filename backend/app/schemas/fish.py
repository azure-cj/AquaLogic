from datetime import datetime

from pydantic import BaseModel


class FishSpeciesBase(BaseModel):
    common_name: str
    scientific_name: str
    photo_url: str | None = None
    description: str | None = None
    ideal_temp_min: float | None = None
    ideal_temp_max: float | None = None
    ideal_ph_min: float | None = None
    ideal_ph_max: float | None = None
    ideal_do_min: float | None = None
    ideal_tds_min: float | None = None
    ideal_tds_max: float | None = None
    diet: str | None = None
    compatibility_notes: str | None = None
    care_tips: str | None = None


class FishSpeciesCreate(FishSpeciesBase):
    pass


class FishSpeciesUpdate(BaseModel):
    common_name: str | None = None
    scientific_name: str | None = None
    photo_url: str | None = None
    description: str | None = None
    ideal_temp_min: float | None = None
    ideal_temp_max: float | None = None
    ideal_ph_min: float | None = None
    ideal_ph_max: float | None = None
    ideal_do_min: float | None = None
    ideal_tds_min: float | None = None
    ideal_tds_max: float | None = None
    diet: str | None = None
    compatibility_notes: str | None = None
    care_tips: str | None = None


class FishSpeciesRead(FishSpeciesBase):
    id: int
    created_at: datetime

    class Config:
        orm_mode = True


class FishAssignmentRequest(BaseModel):
    fish_species_id: int

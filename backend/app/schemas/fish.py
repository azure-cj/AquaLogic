from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator


def validate_preferred_range_order(values: dict) -> dict:
    for minimum_key, maximum_key, label in (
        ("ideal_temp_min", "ideal_temp_max", "temperature"),
        ("ideal_ph_min", "ideal_ph_max", "pH"),
        ("ideal_tds_min", "ideal_tds_max", "TDS"),
    ):
        minimum, maximum = values.get(minimum_key), values.get(maximum_key)
        if minimum is not None and maximum is not None and minimum > maximum:
            raise ValueError(f"Preferred {label} minimum must not exceed maximum")
    return values


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
    ideal_tds_min: float | None = None
    ideal_tds_max: float | None = None
    diet: str | None = None
    diet_type: Literal["Carnivore", "Omnivore", "Herbivore"] | None = None
    compatibility_notes: str | None = None
    care_tips: str | None = None


class FishSpeciesCreate(FishSpeciesBase):
    @model_validator(mode="after")
    def _validate_preferred_range_order(self):
        validate_preferred_range_order(self.model_dump())
        return self


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

    model_config = ConfigDict(from_attributes=True)


class PublicFishSpeciesRead(BaseModel):
    """Customer-safe species projection for public tank displays."""

    common_name: str
    scientific_name: str
    photo_url: str | None = None
    category: str
    description: str | None = None
    diet: str | None = None
    care_tips: str | None = None

    model_config = ConfigDict(from_attributes=True)


class AssignedTankRead(BaseModel):
    id: int
    name: str

    model_config = ConfigDict(from_attributes=True)


class FishSpeciesDirectoryRead(FishSpeciesRead):
    """Authenticated directory response with safe assignment summaries."""

    assigned_tanks: list[AssignedTankRead] = Field(default_factory=list)


class FishImageUploadRead(BaseModel):
    photo_url: str
    content_type: Literal["image/jpeg", "image/png", "image/webp"]
    size_bytes: int


class FishAssignmentRequest(BaseModel):
    fish_species_id: int

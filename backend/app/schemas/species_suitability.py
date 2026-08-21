from datetime import datetime
from typing import Literal

from pydantic import BaseModel, field_validator

from .sensor import make_timestamp_explicit_utc


SpeciesSuitabilityStatus = Literal["suitable", "attention", "unavailable"]
SpeciesSuitabilityReason = Literal[
    "within_preferred_range",
    "below_preferred_minimum",
    "above_preferred_maximum",
    "species_range_missing",
    "no_current_reading",
    "stale_reading",
    "reading_value_missing",
    "invalid_species_range",
]


class SpeciesSuitabilityCheck(BaseModel):
    parameter: Literal["temperature", "ph", "tds"]
    status: SpeciesSuitabilityStatus
    configured: bool
    reason: SpeciesSuitabilityReason
    current_value: float | None = None
    preferred_min: float | None = None
    preferred_max: float | None = None
    unit: str
    message: str


class SpeciesSuitabilitySpecies(BaseModel):
    fish_species_id: int
    common_name: str
    scientific_name: str
    status: SpeciesSuitabilityStatus
    checks: list[SpeciesSuitabilityCheck]


class SpeciesSuitabilityCounts(BaseModel):
    suitable: int
    attention: int
    unavailable: int


class SpeciesSuitabilityReadingReference(BaseModel):
    id: int
    timestamp: datetime
    freshness: Literal["current", "stale"]

    @field_validator("timestamp", mode="after")
    @classmethod
    def normalize_timestamp(cls, value: datetime) -> datetime:
        return make_timestamp_explicit_utc(value)


class SpeciesSuitabilityResponse(BaseModel):
    tank_id: int
    status: SpeciesSuitabilityStatus
    summary_reason: Literal["no_species_assigned"] | None = None
    evaluated_at: datetime
    reading: SpeciesSuitabilityReadingReference | None = None
    species_counts: SpeciesSuitabilityCounts
    species: list[SpeciesSuitabilitySpecies]

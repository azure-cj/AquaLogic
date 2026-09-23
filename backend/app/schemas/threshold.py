from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, model_validator


class ThresholdBase(BaseModel):
    unit: str
    warning_min: float | None = None
    warning_max: float | None = None
    critical_min: float | None = None
    critical_max: float | None = None
    enabled: bool = True

    @model_validator(mode="after")
    def ordered_bounds(self):
        bounds = (
            self.critical_min,
            self.warning_min,
            self.warning_max,
            self.critical_max,
        )
        present = [value for value in bounds if value is not None]
        if any(left >= right for left, right in zip(present, present[1:])):
            raise ValueError(
                "Bounds must be strictly ordered: critical low < warning low < warning high < critical high"
            )
        return self


class ThresholdUpdate(ThresholdBase):
    pass


class ThresholdRead(ThresholdBase):
    model_config = ConfigDict(from_attributes=True)
    parameter: str
    updated_at: datetime


class TankThresholdOverrideUpdate(BaseModel):
    warning_min: float | None
    warning_max: float | None
    critical_min: float | None
    critical_max: float | None
    enabled: bool

    @model_validator(mode="after")
    def ordered_bounds(self):
        bounds = (self.critical_min, self.warning_min, self.warning_max, self.critical_max)
        present = [value for value in bounds if value is not None]
        if any(left >= right for left, right in zip(present, present[1:])):
            raise ValueError(
                "Bounds must be strictly ordered: critical low < warning low < warning high < critical high"
            )
        return self


class EffectiveTankThresholdRead(BaseModel):
    parameter: str
    unit: str
    warning_min: float | None
    warning_max: float | None
    critical_min: float | None
    critical_max: float | None
    enabled: bool
    source: Literal["global", "tank"]
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)

from datetime import datetime

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

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
        pairs = (
            (self.critical_min, self.warning_min),
            (self.warning_min, self.warning_max),
            (self.warning_max, self.critical_max),
        )
        if any(left is not None and right is not None and left > right for left, right in pairs):
            raise ValueError("Bounds must follow critical low â‰¤ warning low â‰¤ warning high â‰¤ critical high")
        return self


class ThresholdUpdate(ThresholdBase):
    pass


class ThresholdRead(ThresholdBase):
    model_config = ConfigDict(from_attributes=True)
    parameter: str
    updated_at: datetime

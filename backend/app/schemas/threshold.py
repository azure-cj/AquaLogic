from datetime import datetime
from pydantic import BaseModel, root_validator


class ThresholdBase(BaseModel):
    unit: str
    warning_min: float | None = None
    warning_max: float | None = None
    critical_min: float | None = None
    critical_max: float | None = None
    enabled: bool = True

    @root_validator
    def ordered_bounds(cls, values):
        cl, wl, wh, ch = (values.get(k) for k in ("critical_min", "warning_min", "warning_max", "critical_max"))
        pairs = ((cl, wl), (wl, wh), (wh, ch))
        if any(left is not None and right is not None and left > right for left, right in pairs):
            raise ValueError("Bounds must follow critical low ≤ warning low ≤ warning high ≤ critical high")
        return values


class ThresholdUpdate(ThresholdBase):
    pass


class ThresholdRead(ThresholdBase):
    parameter: str
    updated_at: datetime
    class Config:
        orm_mode = True

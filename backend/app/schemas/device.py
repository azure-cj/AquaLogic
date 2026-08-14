from pydantic import BaseModel, Field


class DeviceCreate(BaseModel):
    device_id: str = Field(min_length=3, max_length=64, pattern=r"^[A-Za-z0-9_-]+$")
    tank_id: int = Field(gt=0)


class DeviceProvisioned(BaseModel):
    device_id: str
    tank_id: int
    device_key: str

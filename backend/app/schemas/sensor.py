from datetime import datetime

from pydantic import BaseModel


class SensorReadingBase(BaseModel):
    temperature: float
    ph: float
    turbidity: float
    dissolved_oxygen: float
    tds: float
    ammonia: float
    is_mock: bool = False


class SensorReadingCreate(SensorReadingBase):
    timestamp: datetime | None = None


class SensorReadingRead(SensorReadingBase):
    id: int
    tank_id: int
    timestamp: datetime

    class Config:
        orm_mode = True

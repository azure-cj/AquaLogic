from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator


class PushDeviceRegistration(BaseModel):
    model_config = ConfigDict(extra="forbid")

    installation_id: UUID
    fcm_token: str = Field(min_length=1, max_length=4096)
    platform: Literal["android"]

    @field_validator("fcm_token")
    @classmethod
    def reject_blank_or_padded_token(cls, value: str) -> str:
        if not value.strip() or value != value.strip():
            raise ValueError("FCM token must be a non-empty token string")
        return value


class PushDeviceRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    platform: Literal["android"]
    is_active: bool
    last_registered_at: datetime

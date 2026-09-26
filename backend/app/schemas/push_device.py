from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator


class PushDeviceRegistration(BaseModel):
    model_config = ConfigDict(extra="forbid")

    installation_id: UUID
    fcm_token: str = Field(min_length=1, max_length=4096)
    firebase_installation_id: str | None = Field(default=None, min_length=1, max_length=128)
    platform: Literal["android"]

    @field_validator("fcm_token")
    @classmethod
    def reject_blank_or_padded_token(cls, value: str) -> str:
        if not value.strip() or value != value.strip():
            raise ValueError("FCM token must be a non-empty token string")
        return value

    @field_validator("firebase_installation_id")
    @classmethod
    def reject_blank_or_padded_fid(cls, value: str | None) -> str | None:
        if value is not None and (not value.strip() or value != value.strip()):
            raise ValueError("Firebase Installation ID must be a non-empty identifier")
        return value


class PushDeviceRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    platform: Literal["android"]
    is_active: bool
    last_registered_at: datetime

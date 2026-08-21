from datetime import datetime

from pydantic import BaseModel, ConfigDict, EmailStr, Field

from .user import UserRead


class LoginRequest(BaseModel):
    email: EmailStr = Field(max_length=255)
    password: str = Field(min_length=1, max_length=128)


class Token(BaseModel):
    access_token: str
    token_type: str = "bearer"
    expires_at: datetime
    user: UserRead
    must_change_password: bool = False


class ChangePasswordRequest(BaseModel):
    current_password: str = Field(min_length=1, max_length=128)
    new_password: str = Field(min_length=12, max_length=128)


class SetupPasswordRequest(BaseModel):
    token: str = Field(min_length=32, max_length=512)
    password: str = Field(min_length=12, max_length=128)


class LogoutAllRequest(BaseModel):
    current_password: str = Field(min_length=1, max_length=128)


class SetupLinkResponse(BaseModel):
    user: UserRead
    setup_url: str
    expires_at: datetime


class SessionRead(BaseModel):
    id: str
    created_at: datetime
    last_seen_at: datetime | None = None
    expires_at: datetime
    current: bool = False
    user_agent: str | None = None


class AdminSessionRead(BaseModel):
    id: str
    created_at: datetime
    last_seen_at: datetime | None = None
    expires_at: datetime
    user_agent: str | None = None

    model_config = ConfigDict(from_attributes=True)


class RevokeSessionsResponse(BaseModel):
    revoked_count: int


class SecurityAuditEventRead(BaseModel):
    id: int
    event_type: str
    outcome: str
    request_id: str | None = None
    actor_user_id: int | None = None
    target_type: str | None = None
    target_id: str | None = None
    created_at: datetime

from datetime import datetime

from pydantic import BaseModel, ConfigDict, EmailStr, Field


class UserRead(BaseModel):
    id: int
    name: str
    email: EmailStr
    role: str
    is_active: bool
    must_change_password: bool
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


class UserCreate(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    email: EmailStr = Field(max_length=255)
    role: str = "staff"


class UserUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=120)
    role: str | None = None
    is_active: bool | None = None

from datetime import datetime
from pydantic import BaseModel, EmailStr


class CustomerBase(BaseModel):
    name: str
    email: EmailStr | None = None
    phone: str | None = None
    notes: str | None = None
    is_active: bool = True


class CustomerCreate(CustomerBase):
    pass


class CustomerUpdate(BaseModel):
    name: str | None = None
    email: EmailStr | None = None
    phone: str | None = None
    notes: str | None = None
    is_active: bool | None = None


class CustomerRead(CustomerBase):
    id: int
    created_at: datetime
    updated_at: datetime
    class Config:
        orm_mode = True

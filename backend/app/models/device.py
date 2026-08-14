from datetime import datetime

from sqlalchemy import Boolean, DateTime, ForeignKey, String, func
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class RegisteredDevice(Base):
    """A bridge-authenticated device permanently assigned to one tank."""

    __tablename__ = "registered_devices"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    tank_id: Mapped[int] = mapped_column(ForeignKey("tanks.id", ondelete="CASCADE"), nullable=False, index=True)
    key_hash: Mapped[str] = mapped_column(String(64), unique=True, nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    last_seen_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

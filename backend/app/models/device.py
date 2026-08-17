from datetime import datetime

from sqlalchemy import Boolean, DateTime, ForeignKey, Integer, String, Text, UniqueConstraint, func
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


class ActuatorCommand(Base):
    """Immutable target plus mutable lifecycle record for one physical request."""

    __tablename__ = "actuator_commands"

    command_id: Mapped[str] = mapped_column(String(64), primary_key=True)
    device_id: Mapped[str] = mapped_column(
        String(64), ForeignKey("registered_devices.id", ondelete="CASCADE"), nullable=False, index=True
    )
    tank_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("tanks.id", ondelete="CASCADE"), nullable=False, index=True
    )
    actor_user_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True
    )
    actuator: Mapped[str] = mapped_column(String(16), nullable=False)
    action: Mapped[str] = mapped_column(String(24), nullable=False)
    payload_json: Mapped[str] = mapped_column(Text, nullable=False)
    status: Mapped[str] = mapped_column(String(16), nullable=False, index=True)
    requested_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, index=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, index=True)
    executing_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    execution_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    result_json: Mapped[str | None] = mapped_column(Text, nullable=True)
    error_message: Mapped[str | None] = mapped_column(String(500), nullable=True)


class ActuatorState(Base):
    """Latest validated state reported by a bridge for one actuator."""

    __tablename__ = "actuator_states"
    __table_args__ = (UniqueConstraint("device_id", "actuator", name="uq_actuator_states_device_actuator"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    device_id: Mapped[str] = mapped_column(
        String(64), ForeignKey("registered_devices.id", ondelete="CASCADE"), nullable=False, index=True
    )
    tank_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("tanks.id", ondelete="CASCADE"), nullable=False, index=True
    )
    actuator: Mapped[str] = mapped_column(String(16), nullable=False)
    state_json: Mapped[str] = mapped_column(Text, nullable=False)
    refreshed_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, index=True)


class ActuatorStateHistory(Base):
    """Append-only state reports retained for actuator diagnostics."""

    __tablename__ = "actuator_state_history"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    device_id: Mapped[str] = mapped_column(
        String(64), ForeignKey("registered_devices.id", ondelete="CASCADE"), nullable=False, index=True
    )
    tank_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("tanks.id", ondelete="CASCADE"), nullable=False, index=True
    )
    actuator: Mapped[str] = mapped_column(String(16), nullable=False, index=True)
    command_id: Mapped[str | None] = mapped_column(
        String(64), ForeignKey("actuator_commands.command_id", ondelete="SET NULL"), nullable=True
    )
    state_json: Mapped[str] = mapped_column(Text, nullable=False)
    reported_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, index=True)

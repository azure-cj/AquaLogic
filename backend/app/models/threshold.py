from sqlalchemy import (
    Boolean,
    DateTime,
    Float,
    ForeignKey,
    Index,
    Integer,
    String,
    UniqueConstraint,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column
from app.database import Base


class ThresholdConfig(Base):
    __tablename__ = "threshold_configs"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    parameter: Mapped[str] = mapped_column(String(50), unique=True, nullable=False, index=True)
    unit: Mapped[str] = mapped_column(String(30), nullable=False)
    warning_min: Mapped[float | None] = mapped_column(Float, nullable=True)
    warning_max: Mapped[float | None] = mapped_column(Float, nullable=True)
    critical_min: Mapped[float | None] = mapped_column(Float, nullable=True)
    critical_max: Mapped[float | None] = mapped_column(Float, nullable=True)
    enabled: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    updated_at: Mapped[DateTime] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False)


class ThresholdRevision(Base):
    __tablename__ = "threshold_revisions"
    __table_args__ = (
        Index(
            "ix_threshold_revisions_parameter_effective",
            "parameter",
            "effective_from",
        ),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    parameter: Mapped[str] = mapped_column(String(50), nullable=False)
    unit: Mapped[str] = mapped_column(String(30), nullable=False)
    warning_min: Mapped[float | None] = mapped_column(Float, nullable=True)
    warning_max: Mapped[float | None] = mapped_column(Float, nullable=True)
    critical_min: Mapped[float | None] = mapped_column(Float, nullable=True)
    critical_max: Mapped[float | None] = mapped_column(Float, nullable=True)
    enabled: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    effective_from: Mapped[DateTime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
    )


class TankThresholdOverride(Base):
    __tablename__ = "tank_threshold_overrides"
    __table_args__ = (
        UniqueConstraint("tank_id", "parameter", name="uq_tank_threshold_override_parameter"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    tank_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("tanks.id", ondelete="CASCADE"), nullable=False
    )
    parameter: Mapped[str] = mapped_column(String(50), nullable=False)
    # Unit is copied from the global parameter configuration and is never
    # accepted from tank-level API input.
    unit: Mapped[str] = mapped_column(String(30), nullable=False)
    warning_min: Mapped[float | None] = mapped_column(Float, nullable=True)
    warning_max: Mapped[float | None] = mapped_column(Float, nullable=True)
    critical_min: Mapped[float | None] = mapped_column(Float, nullable=True)
    critical_max: Mapped[float | None] = mapped_column(Float, nullable=True)
    enabled: Mapped[bool] = mapped_column(Boolean, nullable=False)
    updated_at: Mapped[DateTime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )


class TankThresholdRevision(Base):
    __tablename__ = "tank_threshold_revisions"
    __table_args__ = (
        Index(
            "ix_tank_threshold_revisions_tank_parameter_effective",
            "tank_id",
            "parameter",
            "effective_from",
        ),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    tank_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("tanks.id", ondelete="CASCADE"), nullable=False
    )
    parameter: Mapped[str] = mapped_column(String(50), nullable=False)
    # A false marker records a reset, so historical evaluation falls back to
    # the global revision timeline from this point onward.
    is_override: Mapped[bool] = mapped_column(Boolean, nullable=False)
    unit: Mapped[str | None] = mapped_column(String(30), nullable=True)
    warning_min: Mapped[float | None] = mapped_column(Float, nullable=True)
    warning_max: Mapped[float | None] = mapped_column(Float, nullable=True)
    critical_min: Mapped[float | None] = mapped_column(Float, nullable=True)
    critical_max: Mapped[float | None] = mapped_column(Float, nullable=True)
    enabled: Mapped[bool | None] = mapped_column(Boolean, nullable=True)
    effective_from: Mapped[DateTime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

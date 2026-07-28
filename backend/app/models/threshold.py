from sqlalchemy import Boolean, DateTime, Float, Index, Integer, String, func
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

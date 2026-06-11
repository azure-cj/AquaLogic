from enum import Enum

from sqlalchemy import Boolean, DateTime, Enum as SqlEnum, ForeignKey, Integer, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class AlertSeverity(str, Enum):
    warning = "warning"
    critical = "critical"


class Alert(Base):
    __tablename__ = "alerts"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    tank_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("tanks.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    reading_id: Mapped[int | None] = mapped_column(
        Integer,
        ForeignKey("sensor_readings.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    parameter: Mapped[str] = mapped_column(String(50), nullable=False, index=True)
    severity: Mapped[AlertSeverity] = mapped_column(
        SqlEnum(AlertSeverity, name="alertseverity", native_enum=False),
        nullable=False,
    )
    message: Mapped[str] = mapped_column(Text, nullable=False)
    is_resolved: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False, index=True)
    created_at: Mapped[DateTime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
    )

    tank: Mapped["Tank"] = relationship("Tank", back_populates="alerts")
    reading: Mapped["SensorReading | None"] = relationship(
        "SensorReading",
        back_populates="alerts",
    )

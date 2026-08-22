from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Index, Integer, String, text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


MONITORING_RESOLUTION_REASONS = (
    "reporting_recovered",
    "monitoring_disabled",
    "tank_retired",
)


class MonitoringIncident(Base):
    """A tank-level interval in which expected reporting stopped."""

    __tablename__ = "monitoring_incidents"
    __table_args__ = (
        Index(
            "uq_monitoring_incidents_active_tank",
            "tank_id",
            unique=True,
            sqlite_where=text("resolved_at IS NULL"),
            postgresql_where=text("resolved_at IS NULL"),
        ),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    tank_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("tanks.id", ondelete="CASCADE"), nullable=False, index=True
    )
    started_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, index=True)
    detected_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, index=True)
    last_reading_received_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    resolved_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True, index=True)
    resolution_reason: Mapped[str | None] = mapped_column(String(32), nullable=True, index=True)
    recovery_reading_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("sensor_readings.id", ondelete="SET NULL"), nullable=True, index=True
    )

    tank: Mapped["Tank"] = relationship("Tank", back_populates="monitoring_incidents")
    recovery_reading: Mapped["SensorReading | None"] = relationship(
        "SensorReading", back_populates="monitoring_recovery_incidents", foreign_keys=[recovery_reading_id]
    )

from sqlalchemy import Boolean, DateTime, Float, ForeignKey, Integer, String, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class SensorReading(Base):
    __tablename__ = "sensor_readings"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    device_id: Mapped[str | None] = mapped_column(
        String(64),
        ForeignKey("registered_devices.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    tank_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("tanks.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    timestamp: Mapped[DateTime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
        index=True,
    )
    received_at: Mapped[DateTime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
        index=True,
    )
    temperature: Mapped[float] = mapped_column(Float, nullable=False)
    ph: Mapped[float] = mapped_column(Float, nullable=False)
    turbidity: Mapped[float] = mapped_column(Float, nullable=False)
    dissolved_oxygen: Mapped[float | None] = mapped_column(Float, nullable=True)
    tds: Mapped[float] = mapped_column(Float, nullable=False)
    ammonia: Mapped[float | None] = mapped_column(Float, nullable=True)
    is_mock: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)

    tank: Mapped["Tank"] = relationship("Tank", back_populates="sensor_readings")
    alerts: Mapped[list["Alert"]] = relationship("Alert", back_populates="reading")

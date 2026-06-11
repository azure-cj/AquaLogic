from sqlalchemy import DateTime, Integer, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class Tank(Base):
    __tablename__ = "tanks"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    name: Mapped[str] = mapped_column(String(100), nullable=False, unique=True)
    location: Mapped[str] = mapped_column(String(150), nullable=False)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[DateTime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
    )

    tank_fish_links: Mapped[list["TankFish"]] = relationship(
        "TankFish",
        back_populates="tank",
        cascade="all, delete-orphan",
        passive_deletes=True,
        overlaps="tanks",
    )
    fish_species: Mapped[list["FishSpecies"]] = relationship(
        "FishSpecies",
        secondary="tank_fish",
        back_populates="tanks",
        overlaps="tank,tank_links,fish_species,tank_fish_links",
    )
    sensor_readings: Mapped[list["SensorReading"]] = relationship(
        "SensorReading",
        back_populates="tank",
        cascade="all, delete-orphan",
        passive_deletes=True,
    )
    alerts: Mapped[list["Alert"]] = relationship(
        "Alert",
        back_populates="tank",
        cascade="all, delete-orphan",
        passive_deletes=True,
    )

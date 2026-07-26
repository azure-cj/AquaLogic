import uuid
from datetime import date

from sqlalchemy import Boolean, Date, DateTime, ForeignKey, Integer, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class Tank(Base):
    __tablename__ = "tanks"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    name: Mapped[str] = mapped_column(String(100), nullable=False, unique=True)
    location: Mapped[str] = mapped_column(String(150), nullable=False)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    public_id: Mapped[str] = mapped_column(String(36), unique=True, nullable=False, default=lambda: str(uuid.uuid4()), index=True)
    is_public: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    customer_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("customers.id", ondelete="SET NULL"), nullable=True, index=True)
    feeding_schedule: Mapped[str | None] = mapped_column(Text, nullable=True)
    public_care_notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    tank_code: Mapped[str | None] = mapped_column(String(32), unique=True, nullable=True, index=True)
    habitat_label: Mapped[str | None] = mapped_column(String(80), nullable=True)
    water_type: Mapped[str | None] = mapped_column(String(20), nullable=True)
    volume_liters: Mapped[int | None] = mapped_column(Integer, nullable=True)
    established_on: Mapped[date | None] = mapped_column(Date, nullable=True)
    hero_image_url: Mapped[str | None] = mapped_column(String(500), nullable=True)
    created_at: Mapped[DateTime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
    )
    customer: Mapped["Customer | None"] = relationship("Customer", back_populates="tanks")

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

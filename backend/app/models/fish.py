from sqlalchemy import DateTime, Float, ForeignKey, Integer, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class FishSpecies(Base):
    __tablename__ = "fish_species"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    common_name: Mapped[str] = mapped_column(String(100), nullable=False, index=True)
    scientific_name: Mapped[str] = mapped_column(String(150), nullable=False)
    photo_url: Mapped[str | None] = mapped_column(String(500), nullable=True)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    ideal_temp_min: Mapped[float | None] = mapped_column(Float, nullable=True)
    ideal_temp_max: Mapped[float | None] = mapped_column(Float, nullable=True)
    ideal_ph_min: Mapped[float | None] = mapped_column(Float, nullable=True)
    ideal_ph_max: Mapped[float | None] = mapped_column(Float, nullable=True)
    ideal_do_min: Mapped[float | None] = mapped_column(Float, nullable=True)
    ideal_tds_min: Mapped[float | None] = mapped_column(Float, nullable=True)
    ideal_tds_max: Mapped[float | None] = mapped_column(Float, nullable=True)
    diet: Mapped[str | None] = mapped_column(Text, nullable=True)
    compatibility_notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    care_tips: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[DateTime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
    )

    tank_links: Mapped[list["TankFish"]] = relationship(
        "TankFish",
        back_populates="fish_species",
        cascade="all, delete-orphan",
        passive_deletes=True,
    )
    tanks: Mapped[list["Tank"]] = relationship(
        "Tank",
        secondary="tank_fish",
        back_populates="fish_species",
        overlaps="tank_links,fish_species,tank_fish_links",
    )


class TankFish(Base):
    __tablename__ = "tank_fish"

    tank_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("tanks.id", ondelete="CASCADE"),
        primary_key=True,
    )
    fish_species_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("fish_species.id", ondelete="CASCADE"),
        primary_key=True,
    )
    added_at: Mapped[DateTime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
    )

    tank: Mapped["Tank"] = relationship(
        "Tank",
        back_populates="tank_fish_links",
        overlaps="tanks",
    )
    fish_species: Mapped[FishSpecies] = relationship(
        FishSpecies,
        back_populates="tank_links",
        overlaps="tanks",
    )

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import FishSpecies

from app.services.demo_species import SAMPLE_FISH_SPECIES, CATEGORY_BY_NAME, _diet_type


def seed_fish_species(db: Session) -> int:
    created = 0
    existing_names = set(db.scalars(select(FishSpecies.common_name)).all())

    for fish_data in SAMPLE_FISH_SPECIES:
        if fish_data["common_name"] in existing_names:
            continue
        directory_data = {
            **fish_data,
            "category": CATEGORY_BY_NAME.get(fish_data["common_name"], "Other"),
            "diet_type": _diet_type(fish_data.get("diet")),
        }
        db.add(FishSpecies(**directory_data))
        created += 1

    return created

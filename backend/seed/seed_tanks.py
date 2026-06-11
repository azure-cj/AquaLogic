from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import Tank

SAMPLE_TANKS = [
    {
        "name": "Tank A",
        "location": "Front Display",
        "description": "Featured community tank near the storefront entrance.",
    },
    {
        "name": "Tank B",
        "location": "Front Display",
        "description": "Small ornamental fish display for quick customer viewing.",
    },
    {
        "name": "Tank C",
        "location": "Breeding Room",
        "description": "Dedicated breeder tank for guppies and livebearers.",
    },
    {
        "name": "Tank D",
        "location": "Breeding Room",
        "description": "Grow-out tank for juvenile fish after separation.",
    },
    {
        "name": "Tank E",
        "location": "Service Area",
        "description": "Temporary holding tank used during maintenance work.",
    },
    {
        "name": "Tank F",
        "location": "Rear Rack",
        "description": "Rack-level tank used for stable-condition species.",
    },
    {
        "name": "Tank G",
        "location": "Rear Rack",
        "description": "Observation tank for sensitive fish requiring close monitoring.",
    },
]


def seed_tanks(db: Session) -> int:
    created = 0
    existing_names = set(db.scalars(select(Tank.name)).all())

    for tank_data in SAMPLE_TANKS:
        if tank_data["name"] in existing_names:
            continue
        db.add(Tank(**tank_data))
        created += 1

    return created

from datetime import date

from sqlalchemy import or_, select
from sqlalchemy.orm import Session

from app.models import Tank

SAMPLE_TANKS = [
    {
        "name": "Riverbank Community",
        "location": "Front Display",
        "description": "A calm planted community aquarium that welcomes visitors at the storefront entrance.",
        "tank_code": "DISPLAY-01",
        "habitat_label": "South American community",
        "water_type": "freshwater",
        "volume_liters": 360,
        "established_on": date(2024, 6, 15),
        "feeding_schedule": "Small community feed at 9:00 AM and 4:00 PM. Skip feeding every Sunday.",
        "public_care_notes": "Please enjoy from the viewing line. Our team checks the planted habitat and water clarity throughout the day.",
        "hero_image_url": "https://images.unsplash.com/photo-1544550285-f813152fb2fd?auto=format&fit=crop&w=1600&q=80",
    },
    {
        "name": "Guppy Gallery",
        "location": "Front Display",
        "description": "A bright livebearer display featuring a constantly changing mix of colourful guppies.",
        "tank_code": "DISPLAY-02",
        "habitat_label": "Livebearer community",
        "water_type": "freshwater",
        "volume_liters": 180,
        "established_on": date(2025, 2, 8),
        "feeding_schedule": "Micro-pellets at 9:30 AM and 3:30 PM; vegetable supplement on Wednesdays.",
        "public_care_notes": "This active display is cared for as a breeding-friendly community. Please avoid tapping on the glass.",
        "hero_image_url": "https://images.unsplash.com/photo-1524704654690-b56c05c78a00?auto=format&fit=crop&w=1600&q=80",
    },
    {
        "name": "Breeder Bay",
        "location": "Breeding Room",
        "description": "A monitored breeding habitat used for selected livebearer pairs and fry development.",
        "tank_code": "BREED-01",
        "habitat_label": "Livebearer breeding habitat",
        "water_type": "freshwater",
        "volume_liters": 240,
        "established_on": date(2024, 11, 22),
        "feeding_schedule": "Three small feeds daily at 8:30 AM, 1:00 PM, and 5:00 PM.",
        "public_care_notes": "Breeding activity means this habitat may be temporarily unavailable for close viewing.",
        "hero_image_url": "https://images.unsplash.com/photo-1535591273668-578e31182c4f?auto=format&fit=crop&w=1600&q=80",
    },
    {
        "name": "Juvenile Grove",
        "location": "Breeding Room",
        "description": "A planted grow-out aquarium that gives juvenile fish space to develop before moving to display habitats.",
        "tank_code": "BREED-02",
        "habitat_label": "Juvenile grow-out habitat",
        "water_type": "freshwater",
        "volume_liters": 300,
        "established_on": date(2025, 5, 5),
        "feeding_schedule": "Fine crumble at 8:00 AM, 12:30 PM, and 5:30 PM.",
        "public_care_notes": "Young fish are sensitive to sudden movement. Viewing is welcome, but please keep the area quiet.",
        "hero_image_url": "https://images.unsplash.com/photo-1520990269335-927144d2f4f4?auto=format&fit=crop&w=1600&q=80",
    },
    {
        "name": "Recovery Reef",
        "location": "Service Area",
        "description": "A quiet recovery and observation aquarium used while our team completes maintenance or acclimation work.",
        "tank_code": "SERVICE-01",
        "habitat_label": "Observation habitat",
        "water_type": "freshwater",
        "volume_liters": 150,
        "established_on": date(2025, 8, 19),
        "feeding_schedule": "Individual care plan; feeding times vary by resident fish.",
        "public_care_notes": "This aquarium is not always open for public viewing because residents may be acclimating or recovering.",
        "hero_image_url": "https://images.unsplash.com/photo-1551244072-5d12893278ab?auto=format&fit=crop&w=1600&q=80",
    },
    {
        "name": "Calmwater Rack",
        "location": "Rear Rack",
        "description": "A stable, low-flow rack habitat for fish that thrive in a quieter environment.",
        "tank_code": "RACK-01",
        "habitat_label": "Low-flow tropical habitat",
        "water_type": "freshwater",
        "volume_liters": 200,
        "established_on": date(2024, 9, 10),
        "feeding_schedule": "Pellets at 9:00 AM and a light evening feed at 5:00 PM.",
        "public_care_notes": "This habitat is maintained for calm, stable conditions and may have reduced lighting at times.",
        "hero_image_url": "https://images.unsplash.com/photo-1520302514089-4a395dbd5c67?auto=format&fit=crop&w=1600&q=80",
    },
    {
        "name": "Observation Point",
        "location": "Rear Rack",
        "description": "A close-monitoring aquarium for sensitive fish and newly introduced community members.",
        "tank_code": "RACK-02",
        "habitat_label": "Sensitive species observation",
        "water_type": "freshwater",
        "volume_liters": 220,
        "established_on": date(2025, 1, 27),
        "feeding_schedule": "Target feed at 9:00 AM and 4:30 PM, adjusted by the care team as needed.",
        "public_care_notes": "Our aquatics team uses this habitat for careful observation. Information may change as residents settle in.",
        "hero_image_url": "https://images.unsplash.com/photo-1544551763-46a013bb70d5?auto=format&fit=crop&w=1600&q=80",
    },
]

LEGACY_TANK_NAMES = (
    "Tank A",
    "Tank B",
    "Tank C",
    "Tank D",
    "Tank E",
    "Tank F",
    "Tank G",
)


def seed_tanks(db: Session) -> int:
    created = 0
    for index, tank_data in enumerate(SAMPLE_TANKS, start=1):
        tank = db.scalar(
            select(Tank).where(
                or_(
                    Tank.tank_code == tank_data["tank_code"],
                    Tank.tank_code == f"TANK-{index:02d}",
                    Tank.name == LEGACY_TANK_NAMES[index - 1],
                )
            )
        )
        if tank is None:
            db.add(Tank(**tank_data))
            created += 1
            continue
        for field, value in tank_data.items():
            setattr(tank, field, value)

    return created

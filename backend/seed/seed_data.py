import os
from sqlalchemy import select

from app.database import Base, SessionLocal, engine
from app.models import User
from app.security import get_password_hash
from seed.seed_fish import seed_fish_species
from seed.seed_dashboard_demo import seed_dashboard_demo
from seed.seed_tanks import seed_tanks
from app.services.decision_engine import ensure_default_thresholds

def seed_admin_user(db) -> bool:
    email = os.getenv("ADMIN_SEED_EMAIL")
    password = os.getenv("ADMIN_SEED_PASSWORD")
    if db.scalar(select(User).where(User.role == "admin")):
        return False
    if not email or not password:
        raise RuntimeError("ADMIN_SEED_EMAIL and ADMIN_SEED_PASSWORD are required to seed an admin")

    user = User(
        name=os.getenv("ADMIN_SEED_NAME", "AquaLogic Administrator"),
        email=email,
        hashed_password=get_password_hash(password),
        role="admin",
    )
    db.add(user)
    return True


def run_seed() -> None:
    Base.metadata.create_all(bind=engine)

    with SessionLocal() as db:
        created_tanks = seed_tanks(db)
        created_fish = seed_fish_species(db)
        created_admin = seed_admin_user(db)
        ensure_default_thresholds(db)
        demo = seed_dashboard_demo(db)

    print("Seed complete")
    print(f"- Tanks created: {created_tanks}")
    print(f"- Fish species created: {created_fish}")
    print(f"- Admin user created: {created_admin}")
    print(f"- Demo fish assignments created: {demo['fish_assignments']}")
    print(f"- Demo sensor readings created: {demo['readings']}")
    print(f"- Demo alerts created: {demo['alerts']}")
    print("- Admin account seeded from environment variables" if created_admin else "- Admin account already exists")


if __name__ == "__main__":
    run_seed()

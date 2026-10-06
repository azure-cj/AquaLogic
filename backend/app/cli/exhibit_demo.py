"""Scoped showcase history and cleanup, without local seed/bootstrap side effects."""
import argparse
from datetime import datetime, timedelta, timezone
from sqlalchemy import delete, func, insert, select, text

from app.config import settings
from app.database import SessionLocal
from app.models import FishSpecies, SensorReading, Tank, TankFish
from app.services.demo_scenarios import PARAMETERS, SCENARIOS, scenario_value
from app.services.demo_species import SAMPLE_FISH_SPECIES, CATEGORY_BY_NAME, _diet_type
from app.services.tank_deletion import stage_retired_tank_deletion, remove_local_hero_image
from app.services.tank_lifecycle import active_device_count, uncleared_actuator_work

SHOWCASES = {
    'SHOW-STABLE': ('Stable Community', ('Neon Tetra', 'Corydoras Catfish', 'Angelfish')),
    'SHOW-WARM-A': ('Warming A', ('Guppy', 'Platy', 'Molly')),
    'SHOW-WARM-B': ('Warming B', ('Angelfish', 'Neon Tetra')),
    'SHOW-BREED': ('Breeding Community', ('Guppy', 'Platy')),
    'SHOW-PH': ('Variable pH', ('Guppy', 'Molly')),
    'SHOW-SPECIES': ('Species Range Conflict', ('Discus', 'Corydoras Catfish')),
    'SHOW-OFFLINE': ('Offline Habitat', ('Betta',)),
}


class ExhibitError(ValueError):
    """Operator-readable refusal, with no database credentials."""


def _locked_show_tanks(db):
    # Acquire all lifecycle locks once, before checking any devices or changing
    # data. SQLite uses its existing writer-lock convention; PostgreSQL locks
    # rows in ID order, shared with device provisioning and the live writer.
    if db.get_bind().dialect.name == 'sqlite':
        db.commit()
        db.execute(text('BEGIN IMMEDIATE'))
    return list(db.scalars(select(Tank).where(Tank.tank_code.startswith('SHOW-'))
                          .order_by(Tank.id).with_for_update().execution_options(populate_existing=True)))


def _require_no_hardware(db, tanks):
    for tank in tanks:
        if active_device_count(db, tank.id):
            raise ExhibitError(f'{tank.tank_code} has an active device; no changes made')
        if uncleared_actuator_work(db, tank.id) is not None:
            raise ExhibitError(f'{tank.tank_code} has unresolved actuator work; no changes made')


def seed(db, *, days=10, replace=False, now=None):
    if days < 1:
        raise ExhibitError('--days must be positive')
    now = now or datetime.now(timezone.utc)
    now = now.replace(microsecond=0)
    existing = _locked_show_tanks(db)
    if any(tank.tank_code not in SCENARIOS for tank in existing):
        raise ExhibitError('Unrecognized SHOW-* tank; inspect status and cleanup before seeding')
    tanks = {tank.tank_code: tank for tank in existing if tank.tank_code in SCENARIOS}
    _require_no_hardware(db, list(tanks.values()))
    for tank in tanks.values():
        if tank.retired_at is not None:
            raise ExhibitError(f'{tank.tank_code} is retired; cleanup before seeding again')
        real = db.scalar(select(SensorReading.id).where(SensorReading.tank_id == tank.id,
                    (SensorReading.is_mock.is_(False) | SensorReading.device_id.is_not(None))).limit(1))
        if real is not None:
            raise ExhibitError(f'{tank.tank_code} has real/device readings; no changes made')
        if not replace and db.scalar(select(SensorReading.id).where(SensorReading.tank_id == tank.id).limit(1)):
            raise ExhibitError('SHOW-* readings already exist; use --replace to regenerate showcase history')

    species = {fish.common_name: fish for fish in db.scalars(select(FishSpecies))}
    catalog = {fish['common_name']: fish for fish in SAMPLE_FISH_SPECIES}
    for code, (label, names) in SHOWCASES.items():
        if code not in tanks:
            tank = Tank(tank_code=code, name=f'Showcase · {label}', location='Exhibit',
                        description='Synthetic showcase measurements', is_public=False)
            db.add(tank)
            tanks[code] = tank
        tanks[code].is_public = False
        for name in names:
            if name not in species:
                data = catalog[name]
                species[name] = FishSpecies(**data, category=CATEGORY_BY_NAME.get(name, 'Other'),
                                            diet_type=_diet_type(data.get('diet')))
                db.add(species[name])
    db.flush()
    for code, (_, names) in SHOWCASES.items():
        tank = tanks[code]
        links = set(db.scalars(select(TankFish.fish_species_id).where(TankFish.tank_id == tank.id)))
        for name in names:
            if species[name].id not in links:
                db.add(TankFish(tank_id=tank.id, fish_species_id=species[name].id))
    if replace:
        db.execute(delete(SensorReading).where(SensorReading.tank_id.in_([t.id for t in tanks.values()])))
    start = now - timedelta(days=days)
    count = 0
    for code, tank in tanks.items():
        # Preserve the offline role's ten-minute reporting outage.
        last = days * 2880 - (20 if SCENARIOS[code] == 'offline' else 0)
        batch = []
        for step in range(last + 1):
            timestamp = start + timedelta(seconds=step * 30)
            batch.append(dict(tank_id=tank.id, timestamp=timestamp, received_at=timestamp,
                              is_mock=True, device_id=None,
                              **{p: scenario_value(code, p, timestamp) for p in PARAMETERS}))
            if len(batch) == 5000:
                db.execute(insert(SensorReading), batch)
                count += len(batch)
                batch.clear()
        if batch:
            db.execute(insert(SensorReading), batch)
            count += len(batch)
    db.commit()
    return count


def cleanup(db, *, now=None):
    tanks = _locked_show_tanks(db)
    _require_no_hardware(db, tanks)
    media = []
    for tank in tanks:
        tank.retired_at = tank.retired_at or now or datetime.now(timezone.utc)
        tank.is_public = False
        media.append(stage_retired_tank_deletion(db, tank))
    db.commit()
    for image_url in media:
        remove_local_hero_image(image_url, settings.media_root)
    return len(tanks)


def status(db, *, stdout=print):
    stdout(f'EXHIBIT_DEMO_UNTIL={settings.exhibit_demo_until.isoformat() if settings.exhibit_demo_until else "unset"}')
    rows = db.execute(select(Tank.tank_code, Tank.name, func.count(SensorReading.id),
                    func.max(SensorReading.timestamp)).outerjoin(SensorReading, SensorReading.tank_id == Tank.id)
                    .where(Tank.tank_code.startswith('SHOW-')).group_by(Tank.id, Tank.tank_code, Tank.name)
                    .order_by(Tank.tank_code))
    for code, name, count, latest in rows:
        latest_utc = (latest.replace(tzinfo=timezone.utc) if latest and latest.tzinfo is None
                      else latest.astimezone(timezone.utc) if latest else None)
        stdout(f'{code} | {name} | readings={count} | latest={latest_utc.isoformat() if latest_utc else "none"} UTC')


def main(argv=None, *, session_factory=SessionLocal, stdout=print, stderr=print):
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    seeder = commands.add_parser('seed')
    seeder.add_argument('--days', type=int, default=10)
    seeder.add_argument('--replace', action='store_true')
    commands.add_parser('cleanup')
    commands.add_parser('status')
    args = parser.parse_args(argv)
    try:
        with session_factory() as db:
            try:
                if args.command == 'seed':
                    stdout(f'Showcase readings seeded: {seed(db, days=args.days, replace=args.replace)}')
                elif args.command == 'cleanup':
                    stdout(f'Showcase tanks deleted: {cleanup(db)}')
                else:
                    status(db, stdout=stdout)
            except Exception:
                db.rollback()
                raise
    except ExhibitError as exc:
        stderr(str(exc))
        return 2
    except Exception:
        stderr('Exhibit command failed; uncommitted changes rolled back (database details omitted)')
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

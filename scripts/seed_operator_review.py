"""Seed only the verified dedicated review database; no production imports/config."""
import json
import os
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from urllib.parse import urlencode

ROOT = Path(__file__).resolve().parents[1]
REVIEW = (ROOT / '.operator-review').resolve()
DATABASE = (REVIEW / 'review.db').resolve()
if REVIEW.parent != ROOT or (ROOT / '.operator-review').is_symlink() or DATABASE.parent != REVIEW or os.environ.get('AQUALOGIC_SYNTHETIC_REVIEW') != '1' or os.environ.get('DATABASE_URL') != f'sqlite:///{DATABASE.as_posix()}':
    raise RuntimeError('Refusing seed outside the dedicated synthetic review database.')
if DATABASE.exists():
    raise RuntimeError('Review database already exists; use the verified reset command.')
sys.path.insert(0, str(ROOT / 'backend'))
from app.database import Base, engine, SessionLocal
from app.models import Alert, AlertSeverity, FishSpecies, SensorReading, Tank, TankThresholdRevision, ThresholdRevision, User
from app.security import get_password_hash
from app.services.analytics import build_fleet_analytics
from app.services.alert_context import build_alert_context
from app.services.decision_engine import ensure_default_thresholds
from fastapi.encoders import jsonable_encoder

now = datetime.now(timezone.utc).replace(microsecond=0)
end = now.replace(minute=0 if now.minute < 30 else 30, second=0)
start = end - timedelta(hours=5)
Base.metadata.create_all(engine)
scenarios = [
    ('Up temperature / mixed species', 'temperature', [26 + i * .4 for i in range(10)], 'mixed'),
    ('Down pH', 'ph', [8 - i * .08 for i in range(10)], 'normal'),
    ('Little change within range', 'temperature', [25] * 10, 'normal'),
    ('Little change outside range', 'temperature', [31] * 10, 'normal'),
    ('Repeated turbidity records', 'turbidity', [12] * 10, 'normal'),
    ('Missing species preferences', 'tds', [180] * 10, 'missing'),
    ('Sparse observations', 'temperature', [24 + i * .4 for i in range(10)], 'sparse'),
    ('Noisy observations', 'temperature', [24, 28, 23, 27, 22, 28, 23, 29, 24, 28], 'normal'),
    ('Threshold revision', 'temperature', [29] * 10, 'revision'),
    ('Delayed observations', 'temperature', [26 + i * .4 for i in range(10)], 'delayed'),
    ('Stale receipt', 'temperature', [25] * 10, 'stale'),
    ('Retired historical context', 'temperature', [31] * 10, 'retired'),
]
with SessionLocal() as db:
    ensure_default_thresholds(db)
    for revision in db.query(ThresholdRevision).all():
        revision.effective_from = start - timedelta(days=1)
    for role in ('admin', 'staff'):
        db.add(User(name=f'Synthetic {role}', email=f'{role}@synthetic.example.com', role=role,
                    hashed_password=get_password_hash('SyntheticReview2026!'), password_changed_at=now))
    warm = FishSpecies(common_name='Fictional warm preference A', scientific_name='Synthetic profile A', ideal_temp_min=28, ideal_temp_max=32, ideal_ph_min=6.5, ideal_ph_max=8, ideal_tds_min=50, ideal_tds_max=400)
    cool = FishSpecies(common_name='Fictional cool preference B', scientific_name='Synthetic profile B', ideal_temp_min=24, ideal_temp_max=27, ideal_ph_min=6.5, ideal_ph_max=8, ideal_tds_min=50, ideal_tds_max=400)
    missing = FishSpecies(common_name='Fictional unconfigured preference C', scientific_name='Synthetic profile C')
    db.add_all([warm,cool,missing]);db.flush()
    manifest=[]
    for index,(name,parameter,values,kind) in enumerate(scenarios,1):
        tank=Tank(name=f'Synthetic {index:02d} · {name}',location='Isolated review rack',is_public=False,
                  retired_at=now if kind=='retired' else None)
        tank.fish_species=[warm,cool] if kind=='mixed' else [missing] if kind=='missing' else [cool]
        db.add(tank);db.flush()
        readings=[]
        for bucket,value in enumerate(values):
            for offset in (0,5) if kind=='sparse' else (0,5,10,15):
                observed=start+timedelta(minutes=bucket*30+offset)
                metrics=dict(temperature=25,ph=7,tds=180,turbidity=2)
                metrics[parameter]=value
                row=SensorReading(tank_id=tank.id,timestamp=observed,received_at=now-timedelta(seconds=10) if kind=='delayed' else observed,is_mock=True,**metrics)
                db.add(row);readings.append(row)
        db.flush()
        metrics=dict(temperature=25,ph=7,tds=180,turbidity=2);metrics[parameter]=values[-1]
        latest=SensorReading(tank_id=tank.id,timestamp=now-timedelta(days=1) if kind=='delayed' else now,
            received_at=now-timedelta(minutes=5) if kind=='stale' else now,is_mock=True,**metrics)
        db.add(latest);db.flush()
        if kind=='revision':
            for at,maximum in ((start,28),(start+timedelta(hours=2.5),32)):
                db.add(TankThresholdRevision(tank_id=tank.id,parameter='temperature',unit='°C',warning_min=20,warning_max=maximum,critical_min=18,critical_max=35,enabled=True,is_override=True,effective_from=at))
        alert_ids=[]
        for number in range(3 if parameter=='turbidity' else 1):
            alert=Alert(tank_id=tank.id,reading_id=readings[min(number*12,len(readings)-1) if parameter=='turbidity' else -1].id,parameter=parameter,severity=AlertSeverity.warning,
                message=f'Synthetic review record: {name}',created_at=start+timedelta(hours=number+1),
                is_resolved=number<2 if parameter=='turbidity' else kind=='retired',
                resolution_source='operator' if (parameter=='turbidity' and number<2) or kind=='retired' else None,
                resolved_at=start+timedelta(hours=number+1,minutes=5) if (parameter=='turbidity' and number<2) or kind=='retired' else None)
            db.add(alert);db.flush();alert_ids.append(alert.id)
        manifest.append(dict(tank_id=tank.id,tank_name=tank.name,parameter=parameter,scenario=kind,alert_ids=alert_ids))
    db.commit()
    for item in manifest:
        result=build_fleet_analytics(db,range_name='custom',start=start,end=end,bucket_seconds=1800,selected_tank_ids=[item['tank_id']],include_retired=True)
        context=build_alert_context(db,db.get(Alert,item['alert_ids'][-1]),evaluated_at=now)
        item['expected_cards']=result['decision_support_insights']['cards']
        item['expected_limitations']=result['decision_support_insights']['limitations']
        item['species_context_at_reset']=context['species_context']
        item['analytics_query']=urlencode(dict(range='custom',start=start.isoformat(),end=end.isoformat(),tanks=item['tank_id'],metric=item['parameter']))
        item['api_query']=urlencode(dict(range='custom',start=start.isoformat(),end=end.isoformat(),tank_id=item['tank_id'],include_retired='true'))
    (REVIEW/'scenarios.json').write_text(json.dumps(jsonable_encoder(dict(label='Synthetic review data',reset_at=now,window_start=start,window_end=end,scenarios=manifest)),indent=2),encoding='utf-8')
print('Dedicated synthetic review database seeded. Fresh context expires after 90 seconds; historical custom windows remain reproducible.')

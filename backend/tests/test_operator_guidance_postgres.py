"""Opt-in integration against a disposable, separately initialized local cluster."""
import os
from datetime import datetime, timedelta, timezone

import pytest
from sqlalchemy import create_engine, inspect
from sqlalchemy.engine import make_url
from sqlalchemy.orm import Session

from app.database import Base, get_db
from app.main import app
from app.models import Alert, AlertSeverity, FishSpecies, SensorReading, Tank, TankThresholdRevision, ThresholdRevision, User
from app.security import get_password_hash
from app.services.decision_engine import ensure_default_thresholds


@pytest.fixture
def postgres_db():
    url=os.getenv('AQUALOGIC_TEST_POSTGRES_URL')
    if not url:
        pytest.skip('Disposable PostgreSQL URL not explicitly configured.')
    parsed=make_url(url)
    if (os.getenv('AQUALOGIC_TEST_POSTGRES_DISPOSABLE')!='1' or parsed.host!='127.0.0.1'
        or parsed.username!='synthetic_review' or parsed.database!='operator_guidance_test'
        or parsed.port is None or parsed.port<55000 or parsed.get_backend_name()!='postgresql'):
        pytest.fail('Refusing a database outside the named disposable local PostgreSQL test boundary.')
    engine=create_engine(url)
    assert not inspect(engine).get_table_names(), 'Test database must be empty; existing tables are never dropped on entry.'
    Base.metadata.create_all(engine)
    try:
        with Session(engine) as db: yield db
    finally:
        Base.metadata.drop_all(engine)
        engine.dispose()


def test_current_species_and_streamed_analytics_on_postgres(postgres_db,client):
    db=postgres_db
    now=datetime.now(timezone.utc)
    end=now.replace(minute=0 if now.minute<30 else 30,second=0,microsecond=0)
    start=end-timedelta(hours=5)
    ensure_default_thresholds(db)
    for revision in db.query(ThresholdRevision): revision.effective_from=start-timedelta(days=1)
    for role in ('admin','staff'):
        db.add(User(name=f'Synthetic {role}',email=f'{role}@synthetic.example.com',role=role,hashed_password=get_password_hash('SyntheticReview2026!')))
    tank=Tank(name='PostgreSQL synthetic tank',location='Disposable test cluster')
    tank.fish_species=[FishSpecies(common_name='Fictional cool',scientific_name='Synthetic PG A',ideal_temp_max=27),FishSpecies(common_name='Fictional warm',scientific_name='Synthetic PG B',ideal_temp_min=28,ideal_temp_max=32)]
    db.add(tank);db.flush()
    for i in range(10):
        for j in range(4):
            stamp=start+timedelta(minutes=i*30+j*5)
            db.add(SensorReading(tank_id=tank.id,timestamp=stamp,received_at=now,temperature=26+i*.4,ph=7,tds=180,turbidity=2,is_mock=True))
    latest=SensorReading(tank_id=tank.id,timestamp=now,received_at=now,temperature=29.6,ph=7,tds=180,turbidity=2,is_mock=True)
    db.add(latest);db.flush()
    # Tank override takes effect halfway through the historical observation window.
    db.add(TankThresholdRevision(tank_id=tank.id,parameter='temperature',is_override=True,unit='°C',warning_min=20,warning_max=29,critical_min=18,critical_max=32,enabled=True,effective_from=start+timedelta(hours=2.5)))
    alerts=[Alert(tank_id=tank.id,reading_id=latest.id,parameter='temperature',severity=AlertSeverity.warning,message='Synthetic PostgreSQL record',created_at=start+timedelta(hours=i+1)) for i in range(3)]
    db.add_all(alerts);db.commit()
    original=app.dependency_overrides.get(get_db)
    app.dependency_overrides[get_db]=lambda:db
    try:
        for role in ('admin','staff'):
            login=client.post('/auth/login',json=dict(email=f'{role}@synthetic.example.com',password='SyntheticReview2026!'))
            assert login.status_code==200
            headers={'Authorization':'Bearer '+login.json()['access_token']}
            detail=client.get(f'/alerts/{alerts[0].id}/context',headers=headers)
            assert detail.status_code==200
            assert detail.json()['species_context']['counts']==dict(assigned=2,evaluable=2,within=1,outside=1,unavailable=0)
            result=client.get(f'/analytics/fleet?range=custom&start={start.isoformat().replace("+00:00","Z")}&end={end.isoformat().replace("+00:00","Z")}&tank_id={tank.id}',headers=headers)
            assert result.status_code==200
            cards=[card for card in result.json()['decision_support_insights']['cards'] if card['parameter']=='temperature']
            assert [card['rule'] for card in cards]==['within_range','repeated_alerts','increasing']
            assert cards[0]['evidence']['percent']==80
            assert any('bounds changed' in text for text in cards[0]['qualifications'])
            assert cards[1]['evidence']['count']==3
            assert cards[2]['evidence']['change']==2.8
            assert cards[2]['evidence']['interval_coverage']==100
            latest.timestamp=now-timedelta(days=1);db.commit()
            stale=client.get(f'/alerts/{alerts[0].id}/context',headers=headers).json()
            assert stale['latest_reading']['reporting_freshness']=='fresh'
            assert stale['species_context']['reason']=='stale_observation'
            latest.timestamp=now;db.commit()
        tank.retired_at=now;db.commit()
        assert client.get(f'/alerts/{alerts[0].id}/context',headers=headers).json()['tank']['lifecycle']=='retired'
        assert client.put(f'/alerts/{alerts[0].id}/resolve',headers=headers).status_code==409
    finally:
        if original is None: app.dependency_overrides.pop(get_db,None)
        else: app.dependency_overrides[get_db]=original

from datetime import datetime, timedelta, timezone
from types import SimpleNamespace as NS

import pytest

from app.models import FishSpecies, SensorReading
from app.services.alert_species_context import build_species_context
from tests.test_alert_context import fixture_alert

NOW = datetime(2026, 10, 2, 12, tzinfo=timezone.utc)


def species(id=1, **bounds):
    return NS(id=id, common_name=f'Fictional preference {id}', **{key: bounds.get(key) for key in
        ('ideal_temp_min', 'ideal_temp_max', 'ideal_ph_min', 'ideal_ph_max', 'ideal_tds_min', 'ideal_tds_max')})


def reading(**changes):
    return NS(**(dict(id=5, timestamp=NOW, received_at=NOW, temperature=25, ph=7, tds=100) | changes))


@pytest.mark.parametrize('parameter,low,high,value', [('temperature','ideal_temp_min','ideal_temp_max',25), ('ph','ideal_ph_min','ideal_ph_max',7), ('tds','ideal_tds_min','ideal_tds_max',100)])
def test_individual_inclusive_one_sided_mixed_preferences(parameter, low, high, value):
    items = [species(1, **{low:value}), species(2, **{high:value}), species(3, **{low:value+1}), species(4), species(5, **{low:value+2,high:value-2})]
    result = build_species_context(NS(fish_species=items + [items[0]]), parameter, reading(), NOW)
    assert result['status'] == 'available'
    assert result['counts'] == dict(assigned=5,evaluable=3,within=2,outside=1,unavailable=2)
    assert result['species'][3]['reason'] == 'species_range_missing'
    assert result['species'][4]['reason'] == 'invalid_species_range'


@pytest.mark.parametrize('stamp,receipt,value,reason', [
    (NOW-timedelta(seconds=91),NOW,25,'stale_observation'),
    (NOW,NOW-timedelta(seconds=91),25,'stale_receipt'),
    (NOW+timedelta(seconds=6),NOW,25,'future_observation'),
    (NOW,NOW,None,'reading_value_missing'),
])
def test_additional_display_gate_keeps_stored_bounds(stamp,receipt,value,reason):
    result=build_species_context(NS(fish_species=[species(ideal_temp_min=20,ideal_temp_max=30)]),'temperature',reading(timestamp=stamp,received_at=receipt,temperature=value),NOW)
    assert result['reason']==reason
    assert result['counts']['unavailable']==1
    assert result['species'][0]['stored_min']==20


@pytest.mark.parametrize('offset',[-90,0,5])
def test_freshness_and_clock_tolerance_edges(offset):
    result=build_species_context(NS(fish_species=[species(ideal_temp_min=20)]),'temperature',reading(timestamp=NOW+timedelta(seconds=offset)),NOW)
    assert result['status']=='available'


def test_no_reading_assignments_and_unsupported():
    tank=NS(fish_species=[species(ideal_temp_min=20)])
    assert build_species_context(tank,'temperature',None,NOW)['reason']=='no_current_reading'
    assert build_species_context(NS(fish_species=[]),'temperature',reading(),NOW)['reason']=='no_species_assigned'
    assert build_species_context(tank,'turbidity',reading(),NOW)['status']=='unsupported'


def test_historical_retired_alert_uses_current_preferences_not_thresholds(db_session, client, auth_headers):
    tank,linked,alert,now=fixture_alert(db_session)
    tank.retired_at=now
    tank.fish_species=[FishSpecies(common_name='Fictional cool preference',scientific_name='Synthetic A',ideal_temp_min=22,ideal_temp_max=24), FishSpecies(common_name='Fictional warm preference',scientific_name='Synthetic B',ideal_temp_min=30,ideal_temp_max=33)]
    latest=SensorReading(tank_id=tank.id,timestamp=now,received_at=now,temperature=31,ph=7,tds=100,turbidity=2)
    db_session.add(latest);db_session.commit()
    data=client.get(f'/alerts/{alert.id}/context',headers=auth_headers).json()
    assert data['species_context']['basis']=='current_assignments_latest_reading'
    assert data['species_context']['reading']['reading_id']==latest.id
    assert data['species_context']['counts']['within']==1
    assert data['species_context']['counts']['outside']==1
    assert data['guidance']['direction']=='above'
    assert data['tank']['lifecycle']=='retired'


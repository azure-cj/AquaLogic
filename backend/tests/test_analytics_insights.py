from datetime import datetime, timedelta, timezone
from types import SimpleNamespace as NS

import pytest

from app.services.analytics_insights import AnalyticsInsightAccumulator

START=datetime(2026,9,1,tzinfo=timezone.utc)
END=START+timedelta(hours=5)


def run(values=None, *, parameter='temperature', skip=(), source_change=False, per_bucket=4, bounds=(20,28), disabled=False, delayed=False, start=START, end=END, histories=None, alerts=(), selected=(), tanks=None):
    values=values if values is not None else [24+i*.2 for i in range(10)]
    tanks=tanks or [NS(id=1,name='Synthetic A')]
    histories=histories or {1:[dict(parameter=parameter,start=start,end=end,warning_min=bounds[0],warning_max=bounds[1],enabled=not disabled,source='global')]}
    accumulator=AnalyticsInsightAccumulator(start,end,tanks,selected,histories,evaluated_at=END+timedelta(days=1))
    for i,value in enumerate(values):
        if i in skip: continue
        for j in range(per_bucket):
            stamp=START+timedelta(minutes=i*30+j*5)
            accumulator.add(1,stamp,stamp+timedelta(days=1) if delayed else stamp,{parameter:value},('source-b' if source_change and i>=5 else 'source-a',False))
    return accumulator.finish(alerts)


def rules(result, parameter='temperature'):
    return [card['rule'] for card in result['cards'] if card['parameter']==parameter]


@pytest.mark.parametrize('parameter,base,step', [('temperature',24,.2),('ph',7,.05),('tds',100,8),('turbidity',5,1)])
@pytest.mark.parametrize('direction', [1,-1])
def test_supported_directions(parameter,base,step,direction):
    result=run([base+direction*i*step for i in range(10)],parameter=parameter)
    assert ('increasing' if direction==1 else 'decreasing') in rules(result,parameter)
    card=next(card for card in result['cards'] if card['rule'] in ('increasing','decreasing'))
    assert card['scope']=='tank' and card['tank_name']=='Synthetic A'
    assert card['evidence']['usable_observations']==40
    assert card['evidence']['interval_coverage']==100
    assert 'percent_change' not in card['evidence']


@pytest.mark.parametrize('value,percent',[(25,100),(31,0)])
def test_little_change_separate_from_health(value,percent):
    result=run([value]*10)
    assert rules(result)==['within_range','little_change']
    assert result['cards'][0]['evidence']['percent']==percent
    assert 'health' not in result['cards'][1]['explanation']


@pytest.mark.parametrize('values', [[24,28,23,27,22,28,23,29,24,28], [24,25,24,23,24,25,24,23,24,25]])
def test_noisy_oscillations_never_stable(values):
    result=run(values)
    assert not set(rules(result)) & {'little_change','increasing','decreasing'}
    assert any('noisy' in item['reason'] for item in result['limitations'])


@pytest.mark.parametrize('kwargs,reason', [({'per_bucket':2},'Insufficient'),({'skip':(2,3)},'substantial gap'),({'skip':(1,2,3)},'Insufficient'),({'source_change':True},'source changed')])
def test_sparse_gaps_sources_suppress(kwargs,reason):
    result=run(**kwargs)
    assert 'increasing' not in rules(result)
    assert any(reason in item['reason'] for item in result['limitations'])


def test_partial_intervals_graph_only_and_delayed_qualified():
    result=run(start=START+timedelta(minutes=10),end=END-timedelta(minutes=10),delayed=True)
    card=next(card for card in result['cards'] if card['rule']=='increasing')
    assert card['evidence']['qualifying_intervals']==8
    assert card['evidence']['usable_observations']==32
    assert card['evidence']['early']==24.3
    assert 'delayed' in card['qualifications'][0]


@pytest.mark.parametrize('bounds,disabled,percent,excluded', [((25,25),False,100,0),((None,25),False,100,0),((25,None),False,100,0),((None,None),False,None,40),((20,30),True,None,40),((30,20),False,None,40)])
def test_inclusive_one_sided_disabled_missing_invalid_operating_bounds(bounds,disabled,percent,excluded):
    result=run([25]*10,bounds=bounds,disabled=disabled)
    within=next((card for card in result['cards'] if card['rule']=='within_range'),None)
    if percent is None:
        assert within is None
        assert next(item for item in result['limitations'] if item['parameter']=='temperature' and item['rule']=='within_range')['excluded']==excluded
    else: assert within['evidence']['percent']==percent


def test_revision_uses_observation_time_discloses_expansion():
    histories={1:[dict(parameter='temperature',start=START,end=START+timedelta(hours=2.5),warning_min=20,warning_max=24,enabled=True,source='global'),dict(parameter='temperature',start=START+timedelta(hours=2.5),end=END,warning_min=20,warning_max=28,enabled=True,source='tank_override')]}
    result=run([25]*10,histories=histories,delayed=True)
    card=result['cards'][0]
    assert card['evidence']['percent']==50
    assert card['evidence']['within']==20
    assert any('Expanded bounds' in text for text in card['qualifications'])


def test_repeated_distinct_records_window_scope_and_order():
    alerts=[dict(id=i,tank_id=1,parameter='temperature') for i in (3,2,1,1)]
    result=run([31]*10,alerts=alerts,tanks=[NS(id=1,name='Synthetic A'),NS(id=2,name='Synthetic B')])
    assert rules(result)==['within_range','repeated_alerts','little_change']
    card=result['cards'][1]
    assert card['title']=='3 temperature alert records were created.'
    assert card['related_alert_ids']==[1,2,3]
    assert run(alerts=alerts,selected=(2,),tanks=[NS(id=1,name='Synthetic A'),NS(id=2,name='Synthetic B')])['cards']==[]


def test_exact_sample_coverage_and_duplicate_timestamp_gate():
    assert 'increasing' in rules(run(per_bucket=3))  # exactly 30 usable observations
    assert 'increasing' in rules(run(skip=(0,9)))  # exactly 80% coverage, no internal gap
    accumulator=AnalyticsInsightAccumulator(START,END,[NS(id=1,name='Synthetic')],[],{},evaluated_at=END)
    for i in range(10):
        stamp=START+timedelta(minutes=i*30)
        for _ in range(10): accumulator.add(1,stamp,stamp,{'temperature':24+i*.2},(None,True))
    assert not set(rules(accumulator.finish([]))) & {'increasing','little_change'}


def test_missing_values_count_as_excluded():
    accumulator=AnalyticsInsightAccumulator(START,END,[NS(id=1,name='Synthetic')],[],{},evaluated_at=END)
    for i in range(40):
        stamp=START+timedelta(minutes=i*5)
        accumulator.add(1,stamp,stamp,{'temperature':None},(None,True))
    result=accumulator.finish([])
    limit=next(item for item in result['limitations'] if item['parameter']=='temperature' and item['rule']=='within_range')
    assert limit['excluded']==40


@pytest.mark.parametrize('parameter,base,notable',[('temperature',25,.5),('ph',7,.15)])
def test_exact_notable_change_is_not_promoted_by_float_rounding(parameter,base,notable):
    result=run([base+i*notable/7 for i in range(10)],parameter=parameter)
    assert not set(rules(result,parameter)) & {'increasing','decreasing','little_change'}


def test_api_scopes_and_batched_history_query_count(db_session,client,auth_headers):
    from sqlalchemy import event
    from app.models import SensorReading, Tank, TankThresholdRevision, Alert, AlertSeverity
    from app.services.analytics import build_fleet_analytics
    from app.services.decision_engine import ensure_default_thresholds
    from app.models import ThresholdRevision
    ensure_default_thresholds(db_session)
    for revision in db_session.query(ThresholdRevision): revision.effective_from=START-timedelta(days=1)
    tanks=[Tank(name='Selected',location='Synthetic'),Tank(name='Fleet context',location='Synthetic')]
    db_session.add_all(tanks);db_session.flush()
    def add_samples(extra):
        for tank in tanks:
            for i in range(10):
                for j in range(extra):
                    stamp=START+timedelta(minutes=i*30,seconds=j*60)
                    db_session.add(SensorReading(tank_id=tank.id,timestamp=stamp,received_at=stamp,temperature=25 if tank==tanks[0] else 31,ph=7,turbidity=2,tds=180))
        db_session.commit()
    add_samples(4)
    db_session.add(TankThresholdRevision(tank_id=tanks[0].id,parameter='temperature',unit='°C',warning_min=25,warning_max=25,critical_min=18,critical_max=30,enabled=True,is_override=True,effective_from=START))
    db_session.add_all([Alert(tank_id=tanks[0].id,parameter='temperature',severity=AlertSeverity.warning,message='Synthetic',created_at=START+timedelta(hours=i+1)) for i in range(3)])
    db_session.commit()
    queries=[]
    def count(*args): queries.append(args[2])
    def measured():
        queries.clear();event.listen(db_session.bind,'before_cursor_execute',count)
        try: result=build_fleet_analytics(db_session,range_name='custom',start=START,end=END,bucket_seconds=3600,selected_tank_ids=[tanks[0].id])
        finally:event.remove(db_session.bind,'before_cursor_execute',count)
        return result,len(queries)
    first,first_count=measured();add_samples(40);second,second_count=measured()
    assert first_count==second_count
    assert all(card['tank_id']==tanks[0].id for card in second['decision_support_insights']['cards'])
    assert first['stats']['temperature']['average']==28  # fleet totals stay fleet-wide
    assert next(card for card in first['decision_support_insights']['cards'] if card['rule']=='within_range' and card['parameter']=='temperature')['evidence']['percent']==100
    assert any(card['rule']=='repeated_alerts' for card in first['decision_support_insights']['cards'])
    assert client.get('/analytics/fleet').status_code==401
    response=client.get(f'/analytics/fleet?range=custom&start={START.isoformat().replace("+00:00","Z")}&end={END.isoformat().replace("+00:00","Z")}&tank_id={tanks[0].id}',headers=auth_headers)
    assert response.status_code==200
    assert response.json()['decision_support_insights']['cards']

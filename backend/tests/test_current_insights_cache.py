from datetime import timedelta

import pytest
from sqlalchemy import create_engine, event
from sqlalchemy.orm import Session

from app.database import Base
from app.models import Tank
from app.services import current_insights as ci


@pytest.fixture(autouse=True)
def isolated_cache():
    ci.clear_current_insights_cache()
    yield
    ci.clear_current_insights_cache()


def test_cache_sorted_ids_ttl_copy_and_bypasses(db_session, monkeypatch):
    db_session.add_all([Tank(name='One', location='Test'), Tank(name='Two', location='Test')])
    db_session.commit()
    clock = [100.]
    monkeypatch.setattr(ci, 'monotonic', lambda: clock[0])
    reading_queries = []

    def track(conn, cursor, statement, parameters, context, executemany):
        if 'sensor_readings' in statement.lower():
            reading_queries.append(statement)

    event.listen(db_session.bind, 'before_cursor_execute', track)
    try:
        first = ci.build_current_insights(db_session, [2, 1, 1])
        assert len(reading_queries) == 1
        cached = ci.build_current_insights(db_session, [1, 2])
        assert cached == first
        assert len(reading_queries) == 1
        cached['tanks'].clear()
        first['tanks'].clear()
        assert len(ci.build_current_insights(db_session)['tanks']) == 2
        clock[0] = 119.999
        ci.build_current_insights(db_session)
        assert len(reading_queries) == 1
        clock[0] = 120
        refreshed = ci.build_current_insights(db_session)
        assert len(reading_queries) == 2
        ci.build_current_insights(db_session, now=refreshed['evaluated_at'] - timedelta(days=1))
        assert len(reading_queries) == 3
        ci.build_current_insights(db_session, use_cache=False)
        assert len(reading_queries) == 4
        ci.build_current_insights(db_session, [1])
        assert len(reading_queries) == 5
    finally:
        event.remove(db_session.bind, 'before_cursor_execute', track)


def test_cache_is_separate_for_databases_and_active_tank_scope(db_session):
    one = Tank(name='Original', location='Test')
    two = Tank(name='Retiring', location='Test')
    db_session.add_all([one, two])
    db_session.commit()
    response = ci.build_current_insights(db_session)
    two.retired_at = response['evaluated_at']
    db_session.commit()
    assert [tank['tank_name'] for tank in ci.build_current_insights(db_session)['tanks']] == ['Original']
    other = create_engine('sqlite://')
    try:
        Base.metadata.create_all(other)
        with Session(other) as db:
            db.add(Tank(id=1, name='Different database', location='Test'))
            db.commit()
            assert ci.build_current_insights(db)['tanks'][0]['tank_name'] == 'Different database'
    finally:
        other.dispose()


def test_cache_is_bounded_per_database(db_session):
    ci.build_current_insights(db_session)
    bind = db_session.get_bind()
    for index in range(ci.INSIGHTS_CACHE_MAX_ENTRIES + 5):
        ci._remember(bind, (index,), {'tanks': []})
    assert len(ci._cache_by_bind[bind]) == ci.INSIGHTS_CACHE_MAX_ENTRIES
    assert ci._cached(bind, (0,)) is None
    assert ci._cached(bind, (ci.INSIGHTS_CACHE_MAX_ENTRIES + 4,)) == {'tanks': []}

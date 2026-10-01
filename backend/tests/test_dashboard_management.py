from datetime import datetime, timedelta, timezone

from sqlalchemy import select

from app.models import (
    Alert,
    AlertSeverity,
    SensorReading,
    Tank,
    ThresholdConfig,
    ThresholdRevision,
    User,
)
from app.security import get_password_hash


def _tank(client, headers, name="Dashboard tank"):
    response = client.post("/tanks", headers=headers, json={"name": name, "location": "Rack"})
    assert response.status_code == 201
    return response.json()


def test_alert_history_filters_and_analytics_buckets(client, auth_headers, db_session):
    tank = _tank(client, auth_headers)
    base = datetime.now(timezone.utc).replace(second=0, microsecond=0) - timedelta(minutes=5)
    reading = SensorReading(tank_id=tank["id"], timestamp=base, received_at=base, temperature=25, ph=7, turbidity=2, dissolved_oxygen=6, tds=100, ammonia=.1)
    db_session.add(reading)
    db_session.flush()
    db_session.add_all([
        SensorReading(tank_id=tank["id"], timestamp=base + timedelta(seconds=10), received_at=base + timedelta(seconds=10), temperature=25, ph=7, turbidity=2, dissolved_oxygen=6, tds=100, ammonia=.1),
        SensorReading(tank_id=tank["id"], timestamp=base + timedelta(seconds=35), received_at=base + timedelta(seconds=35), temperature=25, ph=7, turbidity=2, dissolved_oxygen=6, tds=100, ammonia=.1),
        SensorReading(tank_id=tank["id"], timestamp=base - timedelta(hours=25), received_at=base - timedelta(hours=25), temperature=25, ph=7, turbidity=2, dissolved_oxygen=6, tds=100, ammonia=.1),
    ])
    db_session.add(Alert(tank_id=tank["id"], reading_id=reading.id, parameter="ammonia", severity=AlertSeverity.critical, message="critical ammonia"))
    db_session.commit()
    response = client.get("/alerts/history?parameter=ammonia&severity=critical", headers=auth_headers)
    assert response.status_code == 200
    assert len(response.json()) == 1
    analytics = client.get("/analytics/fleet?range=24h", headers=auth_headers)
    assert analytics.status_code == 200
    payload = analytics.json()
    assert sum(bucket["critical"] for bucket in payload["alert_series"]) == 1
    assert payload["alert_events"][0]["value"] == .1
    assert len(payload["fleet_series"]) in {48, 49}
    assert all(
        datetime.fromisoformat(point["timestamp"].replace("Z", "+00:00")).minute in {0, 30}
        for point in payload["fleet_series"]
    )
    assert payload["window"]["bucket_seconds"] == 900
    assert payload["window"]["water_quality_bucket_seconds"] == 1_800
    assert len(payload["alert_series"]) == 96
    assert any(point["values"]["temperature"] == 25 for point in payload["fleet_series"])
    assert any(point["values"]["temperature"] is None for point in payload["fleet_series"])
    tank_uptime = next(item for item in analytics.json()["uptime"] if item["tank_id"] == tank["id"])
    assert tank_uptime["reported_intervals"] == 2
    assert tank_uptime["previous_reported_intervals"] == 1
    assert tank_uptime["expected_intervals"] == 24 * 120
    assert tank_uptime["status"] == "critical"
    assert payload["uptime_comparison"]["change"] > 0
    assert datetime.fromisoformat(payload["alert_events"][0]["timestamp"].replace("Z", "+00:00")) >= base

    selected = client.get(
        f"/analytics/fleet?range=24h&tank_id={tank['id']}",
        headers=auth_headers,
    )
    assert selected.status_code == 200
    assert selected.json()["tank_series"][0]["tank_name"] == tank["name"]

    custom_start = (base - timedelta(hours=1)).isoformat().replace("+00:00", "Z")
    custom_end = (base + timedelta(hours=1)).isoformat().replace("+00:00", "Z")
    custom = client.get(
        f"/analytics/fleet?range=custom&start={custom_start}&end={custom_end}&bucket=15m",
        headers=auth_headers,
    )
    assert custom.status_code == 200
    assert len(custom.json()["fleet_series"]) in {4, 5}


def test_alert_history_paginates_filtered_results_in_stable_newest_first_order(
    client, auth_headers, db_session
):
    tank = _tank(client, auth_headers, "Paginated alert tank")
    base = datetime.now(timezone.utc).replace(microsecond=0)
    db_session.add_all(
        [
            Alert(
                tank_id=tank["id"],
                parameter="temperature",
                severity=AlertSeverity.warning,
                message="Older temperature alert",
                created_at=base - timedelta(minutes=2),
            ),
            Alert(
                tank_id=tank["id"],
                parameter="ph",
                severity=AlertSeverity.critical,
                message="pH excluded by filter",
                created_at=base,
            ),
            Alert(
                tank_id=tank["id"],
                parameter="temperature",
                severity=AlertSeverity.critical,
                message="Newer temperature alert",
                created_at=base - timedelta(minutes=1),
            ),
        ]
    )
    db_session.commit()

    first_page = client.get(
        "/alerts/history?parameters=temperature&page=1&page_size=1",
        headers=auth_headers,
    )
    second_page = client.get(
        "/alerts/history?parameters=temperature&page=2&page_size=1",
        headers=auth_headers,
    )

    assert first_page.status_code == 200
    first_payload = first_page.json()
    assert len(first_payload["items"]) == 1
    assert first_payload["page"] == 1
    assert first_payload["page_size"] == 1
    assert first_payload["total"] == 2
    assert first_payload["total_pages"] == 2
    assert first_payload["has_previous"] is False
    assert first_payload["has_next"] is True
    assert first_payload["items"][0]["message"] == "Newer temperature alert"
    assert second_page.status_code == 200
    assert second_page.json()["items"][0]["message"] == "Older temperature alert"
    assert second_page.json()["has_previous"] is True
    assert second_page.json()["has_next"] is False


def test_analytics_allows_deferred_device_metrics(client, auth_headers, db_session):
    tank = _tank(client, auth_headers, "Bridge analytics tank")
    db_session.add(
        SensorReading(
            tank_id=tank["id"],
            timestamp=datetime.now(timezone.utc) - timedelta(minutes=1),
            temperature=28.25,
            ph=7.1,
            turbidity=4.0,
            tds=180.0,
            dissolved_oxygen=None,
            ammonia=None,
        )
    )
    db_session.commit()

    response = client.get("/analytics/fleet?range=24h", headers=auth_headers)

    assert response.status_code == 200
    points = response.json()["fleet_series"]
    bridge_point = next(point for point in points if point["values"]["temperature"] == 28.25)
    assert bridge_point["values"]["dissolved_oxygen"] is None
    assert bridge_point["values"]["ammonia"] is None


def test_retired_tanks_leave_live_fleet_but_remain_explicit_historical_analytics(client, auth_headers, db_session):
    active = _tank(client, auth_headers, "Live analytics tank")
    retired = _tank(client, auth_headers, "Retired analytics tank")
    db_session.add(
        SensorReading(
            tank_id=retired["id"],
            timestamp=datetime.now(timezone.utc) - timedelta(minutes=1),
            received_at=datetime.now(timezone.utc) - timedelta(minutes=1),
            temperature=26,
            ph=7,
            turbidity=2,
            tds=120,
        )
    )
    db_session.commit()
    assert client.post(f"/tanks/{retired['id']}/retire", headers=auth_headers, json={}).status_code == 200

    fleet = client.get("/fleet", headers=auth_headers)
    assert fleet.status_code == 200
    assert {item["id"] for item in fleet.json()} == {active["id"]}

    default_analytics = client.get("/analytics/fleet?range=24h", headers=auth_headers)
    assert {item["id"] for item in default_analytics.json()["tanks"]} == {active["id"]}
    excluded_selection = client.get(
        f"/analytics/fleet?range=24h&tank_id={retired['id']}",
        headers=auth_headers,
    )
    assert excluded_selection.status_code == 422

    included = client.get(
        f"/analytics/fleet?range=24h&tank_id={retired['id']}&include_retired=true",
        headers=auth_headers,
    )
    assert included.status_code == 200
    assert {item["id"] for item in included.json()["tanks"]} == {active["id"], retired["id"]}
    assert next(item for item in included.json()["tanks"] if item["id"] == retired["id"])["lifecycle"] == "retired"
    assert included.json()["tank_series"][0]["tank_id"] == retired["id"]


def test_admin_staff_lifecycle_and_threshold_validation(client, db_session):
    admin = User(name="Admin", email="admin@example.com", role="admin", hashed_password=get_password_hash("password123"))
    db_session.add(admin)
    db_session.add(ThresholdConfig(parameter="ammonia", unit="ppm", warning_max=.25, critical_max=.5))
    db_session.commit()
    login = client.post("/auth/login", json={"email": admin.email, "password": "password123"})
    headers = {"Authorization": f"Bearer {login.json()['access_token']}"}
    created = client.post("/users", headers=headers, json={"name": "New Staff", "email": "new@example.com", "role": "staff"})
    assert created.status_code == 201
    new_id = created.json()["user"]["id"]
    assert client.put(f"/users/{new_id}", headers=headers, json={"role": "admin", "is_active": False}).status_code == 200
    assert client.post(f"/users/{new_id}/reset-password", headers=headers).status_code == 200
    invalid = client.put("/thresholds/ammonia", headers=headers, json={"unit": "ppm", "critical_min": 3, "warning_min": 2, "warning_max": 1, "critical_max": 0, "enabled": True})
    assert invalid.status_code == 422
    valid = client.put(
        "/thresholds/ammonia",
        headers=headers,
        json={
            "unit": "ppm",
            "warning_min": None,
            "warning_max": .2,
            "critical_min": None,
            "critical_max": .4,
            "enabled": True,
        },
    )
    assert valid.status_code == 200
    revisions = list(
        db_session.scalars(
            select(ThresholdRevision)
            .where(ThresholdRevision.parameter == "ammonia")
            .order_by(ThresholdRevision.effective_from)
        ).all()
    )
    assert len(revisions) == 2
    assert revisions[-1].warning_max == .2
    revision_boundary = datetime.now(timezone.utc) - timedelta(minutes=20)
    revisions[0].effective_from = revision_boundary - timedelta(minutes=20)
    revisions[1].effective_from = revision_boundary
    db_session.add(Tank(name="Threshold history scope", location="Test rack"))
    db_session.commit()
    threshold_start = (datetime.now(timezone.utc) - timedelta(hours=1)).isoformat().replace("+00:00", "Z")
    threshold_end = (datetime.now(timezone.utc) + timedelta(hours=1)).isoformat().replace("+00:00", "Z")
    analytics = client.get(
        "/analytics/fleet?range=custom"
        f"&start={threshold_start}&end={threshold_end}&bucket=15m",
        headers=headers,
    )
    assert analytics.status_code == 200
    segments = [
        segment
        for segment in analytics.json()["threshold_segments"]
        if segment["parameter"] == "ammonia"
    ]
    assert len(segments) == 2
    assert segments[-1]["warning_max"] == .2


def test_analytics_query_validation(client, auth_headers):
    first = _tank(client, auth_headers, "One")
    second = _tank(client, auth_headers, "Two")
    third = _tank(client, auth_headers, "Three")
    fourth = _tank(client, auth_headers, "Four")
    too_many = "&".join(
        f"tank_id={tank['id']}" for tank in (first, second, third, fourth)
    )
    assert client.get(
        f"/analytics/fleet?range=24h&{too_many}",
        headers=auth_headers,
    ).status_code == 422
    assert client.get(
        "/analytics/fleet?range=custom",
        headers=auth_headers,
    ).status_code == 422
    assert client.get(
        "/analytics/fleet?range=custom"
        "&start=2026-01-01T00:00:00Z&end=2026-03-01T00:00:00Z",
        headers=auth_headers,
    ).status_code == 422


def test_analytics_uses_observation_time_for_metrics_and_receipt_time_for_reporting(
    client, auth_headers, db_session
):
    tank_a = _tank(client, auth_headers, "Observation tank A")
    tank_b = _tank(client, auth_headers, "Observation tank B")
    start = (
        datetime.now(timezone.utc).replace(minute=0, second=0, microsecond=0)
        - timedelta(hours=1)
    )
    end = start + timedelta(hours=3)
    previous_start = start - (end - start)
    recovery_receipt = start + timedelta(minutes=10)

    def reading(tank_id, observed_at, received_at, temperature, ph, turbidity, tds):
        return SensorReading(
            tank_id=tank_id,
            timestamp=observed_at,
            received_at=received_at,
            temperature=temperature,
            ph=ph,
            turbidity=turbidity,
            dissolved_oxygen=None,
            tds=tds,
            ammonia=None,
        )

    recovered = []
    # The backend receives this recovery batch within 15 seconds, while the
    # captured observations land in three separate clock-aligned trend buckets.
    recovered.append(
        reading(
            tank_a["id"], start + timedelta(minutes=15), recovery_receipt,
            20, 7.0, 1.0, 100,
        )
    )
    recovered.extend(
        reading(
            tank_a["id"], start + timedelta(hours=1, minutes=15),
            recovery_receipt + timedelta(seconds=index + 1),
            20, 7.0, 1.0, 100,
        )
        for index in range(10)
    )
    recovered.extend(
        reading(
            tank_b["id"], start + timedelta(minutes=15),
            recovery_receipt + timedelta(seconds=11 + index),
            40, 8.0, 2.0, 200,
        )
        for index in range(3)
    )
    recovered.append(
        reading(
            tank_b["id"], start + timedelta(hours=2, minutes=15),
            recovery_receipt + timedelta(seconds=14),
            30, 7.25, 1.25, 125,
        )
    )
    # This observation belongs in the selected range even though its receipt
    # falls after the range ends.
    recovered.append(
        reading(
            tank_a["id"], start + timedelta(hours=2, minutes=15),
            end + timedelta(days=1), 35, 7.5, 1.5, 150,
        )
    )
    previous_observation = reading(
        tank_a["id"], previous_start + timedelta(minutes=15),
        recovery_receipt + timedelta(seconds=15), 25, 7.2, 1.1, 150,
    )
    # These reports affect receipt-time health only; their observations are
    # outside the metric windows.
    current_health_only = reading(
        tank_a["id"], previous_start - timedelta(days=1),
        start + timedelta(hours=2, minutes=10, seconds=40),
        99, 9.0, 9.0, 999,
    )
    previous_health_only = reading(
        tank_a["id"], previous_start - timedelta(days=2),
        previous_start + timedelta(minutes=20),
        99, 9.0, 9.0, 999,
    )
    db_session.add_all(
        [*recovered, previous_observation, current_health_only, previous_health_only]
    )
    db_session.flush()
    db_session.add(
        Alert(
            tank_id=tank_a["id"],
            reading_id=recovered[0].id,
            parameter="temperature",
            severity=AlertSeverity.critical,
            message="Historical alert creation time",
            created_at=start + timedelta(hours=1, minutes=10),
        )
    )
    db_session.commit()

    start_value = start.isoformat().replace("+00:00", "Z")
    end_value = end.isoformat().replace("+00:00", "Z")
    response = client.get(
        "/analytics/fleet?range=custom&bucket=1h"
        f"&start={start_value}&end={end_value}"
        f"&tank_id={tank_a['id']}&tank_id={tank_b['id']}",
        headers=auth_headers,
    )

    assert response.status_code == 200
    payload = response.json()
    current_points = payload["fleet_series"]
    assert payload["window"]["bucket_seconds"] == 3_600
    assert payload["window"]["water_quality_bucket_seconds"] == 1_800
    assert [point["sample_count"] for point in current_points] == [4, 0, 10, 0, 2, 0]
    assert [point["contributor_count"] for point in current_points] == [2, 0, 1, 0, 2, 0]
    assert [point["values"]["temperature"] for point in current_points] == [35, None, 20, None, 32.5, None]
    assert [point["values"]["ph"] for point in current_points] == [7.75, None, 7.0, None, 7.375, None]
    assert [point["values"]["turbidity"] for point in current_points] == [1.75, None, 1.0, None, 1.375, None]
    assert [point["values"]["tds"] for point in current_points] == [175, None, 100, None, 137.5, None]
    assert [point["sample_count"] for point in payload["previous_fleet_series"]] == [1, 0, 0, 0, 0, 0]
    assert [
        datetime.fromisoformat(point["timestamp"].replace("Z", "+00:00"))
        for point in current_points
    ] == [start + timedelta(minutes=30 * index) for index in range(6)]

    temperature_stats = payload["stats"]["temperature"]
    assert temperature_stats["average"] == 25.3125
    assert temperature_stats["minimum"] == 20
    assert temperature_stats["maximum"] == 40
    assert temperature_stats["previous_average"] == 25
    assert temperature_stats["absolute_change"] == 0.3125
    assert temperature_stats["percent_change"] == 1.25

    selected_series = {item["tank_id"]: item["series"] for item in payload["tank_series"]}
    tank_a_series = selected_series[tank_a["id"]]
    tank_b_series = selected_series[tank_b["id"]]
    assert [point["sample_count"] for point in tank_a_series] == [1, 0, 10, 0, 1, 0]
    assert [point["values"]["temperature"] for point in tank_a_series] == [20, None, 20, None, 35, None]
    assert [point["sample_count"] for point in tank_b_series] == [3, 0, 0, 0, 1, 0]
    assert [point["values"]["temperature"] for point in tank_b_series] == [40, None, None, None, 30, None]
    driver = payload["insights"]["primary_driver_by_metric"]["temperature"]
    assert driver == tank_a["id"]

    # All backlog deliveries are in receipt bucket 0, while another report for
    # tank A arrived in bucket 2. Each tank has a receipt-time gap run.
    tank_a_uptime = next(
        item for item in payload["uptime"] if item["tank_id"] == tank_a["id"]
    )
    assert tank_a_uptime["reported_intervals"] == 2
    assert tank_a_uptime["previous_reported_intervals"] == 1
    assert payload["insights"]["reporting_gap_count"] == 2

    # Alert markers remain placed by Alert.created_at, independent of either
    # the linked reading's observation or receipt time.
    assert [bucket["critical"] for bucket in payload["alert_series"]] == [0, 1, 0]
    expected_alert_time = (
        start + timedelta(hours=1, minutes=10)
    ).isoformat().replace("+00:00", "Z")
    assert payload["alert_events"][0]["timestamp"] == expected_alert_time


def test_analytics_half_hour_buckets_align_and_include_partial_current_bucket(
    client, auth_headers, db_session
):
    tank = _tank(client, auth_headers, "Half-hour analytics tank")
    start = datetime.now(timezone.utc).replace(minute=17, second=0, microsecond=0)
    end = start + timedelta(minutes=175)
    recent_receipt = end - timedelta(minutes=5)

    def reading(observed_at, received_at):
        return SensorReading(
            tank_id=tank["id"],
            timestamp=observed_at,
            received_at=received_at,
            temperature=25,
            ph=7.1,
            turbidity=2,
            dissolved_oxygen=None,
            tds=180,
            ammonia=None,
        )

    db_session.add_all(
        [
            reading(start, recent_receipt),
            reading(start + timedelta(minutes=12), recent_receipt),
            reading(start + timedelta(minutes=13), recent_receipt),
            reading(start + timedelta(minutes=43), recent_receipt),
            reading(start + timedelta(minutes=103), recent_receipt),
            reading(start + timedelta(minutes=164), recent_receipt),
            # This row is outside the observation window but still reports now.
            reading(end, recent_receipt),
            # Historical capture timestamp, but an independently timed report.
            reading(start - timedelta(days=1), start + timedelta(minutes=5)),
        ]
    )
    db_session.commit()

    start_value = start.isoformat().replace("+00:00", "Z")
    end_value = end.isoformat().replace("+00:00", "Z")
    response = client.get(
        "/analytics/fleet?range=custom&bucket=1h"
        f"&start={start_value}&end={end_value}",
        headers=auth_headers,
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["window"]["bucket_seconds"] == 3_600
    assert payload["window"]["water_quality_bucket_seconds"] == 1_800
    points = payload["fleet_series"]
    assert [point["sample_count"] for point in points] == [2, 1, 1, 0, 1, 0, 1]
    assert [
        datetime.fromisoformat(point["timestamp"].replace("Z", "+00:00"))
        for point in points
    ] == [
        start.replace(minute=0) + timedelta(minutes=30 * index)
        for index in range(7)
    ]
    assert [datetime.fromisoformat(point["timestamp"].replace("Z", "+00:00")).minute for point in points] == [0, 30, 0, 30, 0, 30, 0]
    assert sum(point["sample_count"] for point in points) == 6
    # Despite backfilled observations sharing a receipt time, monitoring sees
    # only the two actual reporting intervals; alert/report bucket resolution
    # remains at the requested one hour.
    uptime = next(item for item in payload["uptime"] if item["tank_id"] == tank["id"])
    assert uptime["reported_intervals"] == 2
    assert len(payload["alert_series"]) == 3
    assert payload["insights"]["reporting_gap_count"] == 1

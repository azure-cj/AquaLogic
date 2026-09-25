import json
import logging
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest.mock import patch

import pytest

sys.path.insert(0, str(Path(__file__).parents[1]))
import esp32_bridge as bridge


FIXTURE = Path(__file__).parents[2] / "backend" / "tests" / "fixtures" / "esp32_data.json"


@pytest.fixture(autouse=True)
def _reset_bridge_backlog_anchor():
    bridge._last_live_reading_at = None
    yield
    bridge._last_live_reading_at = None


def test_translates_only_supported_esp32_fields():
    payload = bridge.translate_esp32_payload(json.loads(FIXTURE.read_text()))
    assert set(payload) == {"temperature", "ph", "turbidity", "tds", "observed_at"}
    assert payload["temperature"] == 26.75
    assert payload["tds"] == 221.0


@pytest.mark.parametrize("payload", [{}, {"temp_c": "bad", "ph_value": 7, "turbidity_ntu": 1, "tds_ppm": 1}, {"temp_c": 25, "ph_value": 15, "turbidity_ntu": 1, "tds_ppm": 1}])
def test_rejects_invalid_esp32_values(payload):
    with pytest.raises(bridge.BridgeError):
        bridge.translate_esp32_payload(payload)


def test_unreachable_esp32_does_not_submit():
    config = {"esp32_data_url": "http://esp32.invalid/data", "aqualogic_backend_url": "https://api.example", "device_key": "test", "timeout_seconds": 1}
    with patch.object(bridge, "fetch_json", side_effect=bridge.URLError("offline")), patch.object(bridge, "post_reading") as submit:
        with pytest.raises(bridge.URLError):
            bridge.run_once(config)
    submit.assert_not_called()


def test_backlog_drain_runs_only_after_a_successful_live_poll():
    config = {"esp32_data_url": "http://esp32.invalid/data", "aqualogic_backend_url": "https://api.example", "device_key": "test", "timeout_seconds": 1, "actuator_enabled": False}
    with patch.object(bridge, "poll_sensor_once", side_effect=bridge.URLError("offline")), \
        patch.object(bridge, "drain_backlog") as drain:
        with pytest.raises(bridge.URLError):
            bridge.run_once(config)
    drain.assert_not_called()
    with patch.object(bridge, "poll_sensor_once"), patch.object(bridge, "drain_backlog") as drain:
        bridge.run_once(config)
    drain.assert_called_once_with(config)


def test_invalid_esp32_json_is_reported():
    with patch("esp32_bridge.urlopen") as open_url:
        response = open_url.return_value.__enter__.return_value
        response.status = 200
        response.read.return_value = b"not json"
        with pytest.raises(bridge.BridgeError, match="invalid JSON"):
            bridge.fetch_json("http://esp32.local/data", 1)


def test_invalid_polling_configuration_is_rejected(tmp_path):
    path = tmp_path / "bridge-config.json"
    path.write_text(json.dumps({"esp32_data_url": "http://esp32/data", "aqualogic_backend_url": "https://api.example", "device_key": "key", "poll_interval_seconds": "fast"}))
    with pytest.raises(bridge.BridgeError, match="Polling interval"):
        bridge.load_config(path)


def test_pump_manual_test_flag_defaults_to_false(tmp_path):
    path = tmp_path / "bridge-config.json"
    path.write_text(json.dumps({
        "esp32_data_url": "http://esp32/data",
        "aqualogic_backend_url": "https://api.example",
        "device_key": "key",
    }))
    config = bridge.load_config(path)
    assert config["pump_manual_test_enabled"] is False
    assert config["pump_completion_timeout_seconds"] == bridge.PUMP_COMPLETION_TIMEOUT_DEFAULT_SECONDS


def test_pump_completion_timeout_is_bounded(tmp_path):
    path = tmp_path / "bridge-config.json"
    path.write_text(json.dumps({
        "esp32_data_url": "http://esp32/data",
        "aqualogic_backend_url": "https://api.example",
        "device_key": "key",
        "pump_completion_timeout_seconds": 121,
    }))
    with pytest.raises(bridge.BridgeError, match="pump_completion_timeout_seconds"):
        bridge.load_config(path)


def command(actuator, action, payload):
    return {
        "command_id": f"command-{actuator}-{action}",
        "device_id": "esp32-test-01",
        "actuator": actuator,
        "action": action,
        "payload": payload,
        "expires_at": (datetime.now(timezone.utc) + timedelta(minutes=1)).isoformat(),
    }


@pytest.mark.parametrize(
    ("raw", "path", "query"),
    [
        (command("uv", "on", {}), "/uv/on", {}),
        (command("uv", "off", {}), "/uv/off", {}),
        (command("uv", "timer", {"duration_ms": 15_000}), "/uv/timer", {"duration": "15000"}),
        (command("uv", "schedule", {"enabled": True, "on_time": "08:00", "off_time": "18:30"}), "/uv/schedule", {"enabled": "1", "onH": "08", "onM": "00", "offH": "18", "offM": "30"}),
        (command("led", "on", {}), "/led/on", {}),
        (command("led", "off", {}), "/led/off", {}),
        (command("led", "timer", {"duration_ms": 60_000}), "/led/timer", {"duration": "60000"}),
        (command("led", "schedule", {"enabled": False, "on_time": "07:05", "off_time": "22:10"}), "/led/schedule", {"enabled": "0", "onH": "07", "onM": "05", "offH": "22", "offM": "10"}),
        (command("feeder", "feed_now", {}), "/feeder/feed", {}),
        (command("feeder", "config", {"open_angle": 125, "duration_ms": 1000}), "/feeder/config", {"angle": "125", "duration": "1000"}),
        (command("feeder", "schedule", {"slots": [{"enabled": True, "time": "08:00"}, {"enabled": False, "time": "12:30"}, {"enabled": True, "time": "18:00"}]}), "/feeder/schedule", {"h0": "08", "m0": "00", "e0": "1", "h1": "12", "m1": "30", "e1": "0", "h2": "18", "m2": "00", "e2": "1"}),
        (command("pump_a", "dispense", {}), "/syringeA/dispense", {}),
        (command("pump_a", "stop", {}), "/syringeA/stop", {}),
        (command("pump_a", "retract", {}), "/syringeA/retract", {}),
        (command("pump_b", "dispense", {}), "/syringeB/dispense", {}),
        (command("pump_b", "stop", {}), "/syringeB/stop", {}),
        (command("pump_b", "retract", {}), "/syringeB/retract", {}),
    ],
)
def test_translates_each_allowlisted_firmware_endpoint(raw, path, query):
    translated = bridge.translate_actuator_command(raw)
    assert translated["path"] == path
    assert translated["query"] == query


@pytest.mark.parametrize(
    "raw",
    [
        command("syringeA", "dispense", {}),
        command("feeder", "test", {}),
        command("ph", "auto", {}),
        {**command("uv", "on", {}), "expires_at": (datetime.now(timezone.utc) - timedelta(seconds=1)).isoformat()},
        command("uv", "timer", {"duration_ms": 86_400_001}),
        command("feeder", "config", {"open_angle": 181, "duration_ms": 1000}),
        command("pump_a", "dispense", {"volume_ml": 1}),
        command("pump_b", "dispense", {"unexpected": True}),
        command("pump_a", "stop", {"unexpected": True}),
    ],
)
def test_rejects_non_allowlisted_or_invalid_actuator_commands(raw):
    with pytest.raises(bridge.BridgeError):
        bridge.translate_actuator_command(raw)


def test_translates_and_validates_firmware_status_payloads():
    light = bridge._translate_light_status({
        "led_on": True,
        "remaining_ms": 5000,
        "total_on_ms": 10000,
        "schedule_enabled": True,
        "sched_on": "08:00",
        "sched_off": "18:00",
    })
    assert light["on"] is True
    assert light["on_time"] == "08:00"
    feeder = bridge._translate_feeder_status({
        "feeding": False,
        "feed_count": 2,
        "last_fed": "Never",
        "open_angle": 125,
        "duration_ms": 1000,
        "schedule": [
            {"hour": 8, "minute": 0, "enabled": True},
            {"hour": 12, "minute": 30, "enabled": False},
            {"hour": 18, "minute": 0, "enabled": True},
        ],
    })
    assert feeder["schedule"][1] == {"enabled": False, "time": "12:30"}
    pump = bridge._translate_pump_status({
        "active": True,
        "dose_count": 2,
        "last_dispensed": "12:34:56",
        "volume_ml": 1.0,
        "schedule": [
            {"hour": 8, "minute": 0, "enabled": False},
            {"hour": 12, "minute": 30, "enabled": False},
            {"hour": 18, "minute": 0, "enabled": False},
        ],
    })
    assert pump == {"active": True, "dose_count": 2, "last_dispensed": "12:34:56", "volume_ml": 1.0}


@pytest.mark.parametrize(
    "status",
    [
        {
            "active": False,
            "dose_count": 0,
            "last_dispensed": "Never",
            "volume_ml": 1.0,
            "remaining_ml": 5.0,
            "capacity_ml": 5.0,
            "schedule": [
                {"hour": 8, "minute": 0, "enabled": False},
                {"hour": 14, "minute": 0, "enabled": False},
                {"hour": 20, "minute": 0, "enabled": False},
            ],
        },
        {
            "active": False,
            "dose_count": 0,
            "last_dispensed": "Never",
            "volume_ml": 1.0,
            "remaining_ml": 5.0,
            "capacity_ml": 5.0,
            "schedule": [
                {"hour": 9, "minute": 0, "enabled": False},
                {"hour": 15, "minute": 0, "enabled": False},
                {"hour": 21, "minute": 0, "enabled": False},
            ],
        },
    ],
    ids=["pump_a-current-firmware", "pump_b-current-firmware"],
)
def test_translates_current_firmware_pump_status_with_extra_fields(status):
    # Current /syringeA/status and /syringeB/status include remaining_ml and
    # capacity_ml in addition to the fields used by the bridge.
    assert bridge._translate_pump_status(status) == {
        "active": False,
        "dose_count": 0,
        "last_dispensed": "Never",
        "volume_ml": 1.0,
    }


def test_translates_pump_status_with_future_firmware_fields():
    status = {
        "active": False,
        "dose_count": 0,
        "last_dispensed": "Never",
        "volume_ml": 1.0,
        "schedule": [
            {"hour": 8, "minute": 0, "enabled": False},
            {"hour": 14, "minute": 0, "enabled": False},
            {"hour": 20, "minute": 0, "enabled": False},
        ],
        "future_firmware_field": {"value": "ignored by bridge"},
    }
    assert bridge._translate_pump_status(status)["active"] is False


def test_successful_command_is_sent_once_and_reported():
    config = {
        "esp32_data_url": "http://192.168.1.50/data",
        "aqualogic_backend_url": "https://api.example/api",
        "device_key": "key",
        "timeout_seconds": 1,
    }
    pending = command("uv", "on", {})
    with patch.object(bridge, "_pending_commands", return_value=[pending]), \
        patch.object(bridge, "_mark_executing") as claim, \
        patch.object(bridge, "refresh_actuator_states") as refresh, \
        patch.object(bridge, "_report_succeeded") as succeeded, \
        patch.object(bridge, "fetch_json", return_value={"led": "on"}) as fetch:
        assert bridge.process_pending_actuator_commands(config) == 1
    claim.assert_called_once_with(config, pending["command_id"])
    fetch.assert_called_once_with("http://192.168.1.50/uv/on", 1.0)
    refresh.assert_called_once_with(config, command_id=pending["command_id"])
    succeeded.assert_called_once()


def test_schedule_command_is_forwarded_once_with_exact_device_times():
    config = {
        "esp32_data_url": "http://192.168.1.50/data",
        "aqualogic_backend_url": "https://api.example/api",
        "device_key": "key",
        "timeout_seconds": 1,
    }
    pending = command(
        "feeder",
        "schedule",
        {
            "slots": [
                {"enabled": True, "time": "08:05"},
                {"enabled": False, "time": "12:30"},
                {"enabled": True, "time": "18:45"},
            ]
        },
    )
    with patch.object(bridge, "_pending_commands", return_value=[pending]), \
        patch.object(bridge, "_mark_executing"), \
        patch.object(bridge, "refresh_actuator_states"), \
        patch.object(bridge, "_report_succeeded") as succeeded, \
        patch.object(bridge, "fetch_json", return_value={"schedule": "saved"}) as fetch:
        assert bridge.process_pending_actuator_commands(config) == 1
    fetch.assert_called_once_with(
        "http://192.168.1.50/feeder/schedule?h0=08&m0=05&e0=1&h1=12&m1=30&e1=0&h2=18&m2=45&e2=1",
        1.0,
    )
    succeeded.assert_called_once()


def pump_status(*, active=False, dose_count=2, volume_ml=1.0):
    return {
        "active": active,
        "dose_count": dose_count,
        "last_dispensed": "12:34:56",
        "volume_ml": volume_ml,
        "remaining_ml": 5.0,
        "capacity_ml": 5.0,
        "schedule": [
            {"hour": 8, "minute": 0, "enabled": False},
            {"hour": 12, "minute": 30, "enabled": False},
            {"hour": 18, "minute": 0, "enabled": False},
        ],
    }


def test_pump_dispense_waits_for_configured_volume_without_retrying_dispense():
    config = {
        "esp32_data_url": "http://192.168.1.50/data",
        "aqualogic_backend_url": "https://api.example/api",
        "device_key": "key",
        "timeout_seconds": 1,
        "pump_manual_test_enabled": True,
        "pump_completion_timeout_seconds": 5,
    }
    pending = command("pump_a", "dispense", {})
    with patch.object(bridge, "_pending_commands", return_value=[pending]), \
        patch.object(bridge, "_mark_executing"), \
        patch.object(bridge, "refresh_actuator_states") as refresh, \
        patch.object(bridge, "_report_succeeded") as succeeded, \
        patch.object(bridge, "fetch_json", side_effect=[
            pump_status(dose_count=2),
            pump_status(dose_count=2),
            {"dispensed": True},
            pump_status(active=True, dose_count=3),
            pump_status(active=False, dose_count=3),
        ]) as fetch, \
        patch.object(bridge.time, "sleep") as sleep:
        assert bridge.process_pending_actuator_commands(config) == 1
    assert [call.args[0] for call in fetch.call_args_list] == [
        "http://192.168.1.50/syringeA/status",
        "http://192.168.1.50/syringeB/status",
        "http://192.168.1.50/syringeA/dispense",
        "http://192.168.1.50/syringeA/status",
        "http://192.168.1.50/syringeA/status",
    ]
    sleep.assert_called_once_with(bridge.PUMP_STATUS_POLL_INTERVAL_SECONDS)
    refresh.assert_called_once_with(config, command_id=pending["command_id"])
    succeeded.assert_called_once()
    assert succeeded.call_args.args[1] == pending["command_id"]
    assert succeeded.call_args.args[2]["configured_volume_ml"] == 1.0
    assert succeeded.call_args.args[2]["completion_observed"] is True


def test_pump_completion_timeout_reports_unknown_and_safety_stop_is_not_a_retry():
    config = {
        "esp32_data_url": "http://192.168.1.50/data",
        "aqualogic_backend_url": "https://api.example/api",
        "device_key": "key",
        "timeout_seconds": 1,
        "pump_manual_test_enabled": True,
        "pump_completion_timeout_seconds": 5,
    }
    pending = command("pump_b", "dispense", {})
    with patch.object(bridge, "_pending_commands", return_value=[pending]), \
        patch.object(bridge, "_mark_executing"), \
        patch.object(bridge, "_report_outcome_unknown") as unknown, \
        patch.object(bridge, "refresh_actuator_states"), \
        patch.object(bridge, "fetch_json", side_effect=[
            pump_status(dose_count=2),
            pump_status(dose_count=2),
            {"dispensed": True},
            pump_status(active=True, dose_count=3),
            {"stopped": True},
        ]) as fetch, \
        patch.object(bridge.time, "monotonic", side_effect=[0, 6]):
        assert bridge.process_pending_actuator_commands(config) == 0
    assert [call.args[0] for call in fetch.call_args_list] == [
        "http://192.168.1.50/syringeA/status",
        "http://192.168.1.50/syringeB/status",
        "http://192.168.1.50/syringeB/dispense",
        "http://192.168.1.50/syringeB/status",
        "http://192.168.1.50/syringeB/stop",
    ]
    unknown.assert_called_once()


def test_pump_actions_are_failed_without_hardware_call_when_disabled():
    config = {
        "esp32_data_url": "http://192.168.1.50/data",
        "aqualogic_backend_url": "https://api.example/api",
        "device_key": "key",
        "timeout_seconds": 1,
        "pump_manual_test_enabled": False,
    }
    pending = command("pump_b", "retract", {})
    with patch.object(bridge, "_pending_commands", return_value=[pending]), \
        patch.object(bridge, "_mark_executing") as claim, \
        patch.object(bridge, "_report_failed") as failed, \
        patch.object(bridge, "fetch_json") as fetch:
        assert bridge.process_pending_actuator_commands(config) == 0
    claim.assert_called_once_with(config, pending["command_id"])
    failed.assert_called_once_with(config, pending["command_id"], "Pump manual testing is disabled in bridge configuration")
    fetch.assert_not_called()


def test_pump_stop_and_retract_are_single_exact_requests():
    config = {
        "esp32_data_url": "http://192.168.1.50/data",
        "aqualogic_backend_url": "https://api.example/api",
        "device_key": "key",
        "timeout_seconds": 1,
        "pump_manual_test_enabled": True,
    }
    pending = [command("pump_a", "stop", {}), command("pump_b", "retract", {})]
    with patch.object(bridge, "_pending_commands", return_value=pending), \
        patch.object(bridge, "_mark_executing"), \
        patch.object(bridge, "refresh_actuator_states"), \
        patch.object(bridge, "_report_succeeded") as succeeded, \
        patch.object(bridge, "fetch_json", side_effect=[{"stopped": True}, {"retracted": True}]) as fetch:
        assert bridge.process_pending_actuator_commands(config) == 2
    assert [call.args[0] for call in fetch.call_args_list] == [
        "http://192.168.1.50/syringeA/stop",
        "http://192.168.1.50/syringeB/retract",
    ]
    assert succeeded.call_count == 2


def test_physical_request_timeout_reports_unknown_without_retrying_hardware():
    config = {
        "esp32_data_url": "http://192.168.1.50/data",
        "aqualogic_backend_url": "https://api.example/api",
        "device_key": "key",
        "timeout_seconds": 1,
    }
    pending = command("feeder", "feed_now", {})
    with patch.object(bridge, "_pending_commands", return_value=[pending]), \
        patch.object(bridge, "_mark_executing"), \
        patch.object(bridge, "_report_outcome_unknown") as unknown, \
        patch.object(bridge, "refresh_actuator_states"), \
        patch.object(bridge, "fetch_json", side_effect=bridge.URLError("offline")) as fetch:
        assert bridge.process_pending_actuator_commands(config) == 0
    fetch.assert_called_once_with("http://192.168.1.50/feeder/feed", 1.0)
    unknown.assert_called_once()


def test_malformed_terminal_response_reports_unknown_without_a_second_request():
    config = {
        "esp32_data_url": "http://192.168.1.50/data",
        "aqualogic_backend_url": "https://api.example/api",
        "device_key": "key",
        "timeout_seconds": 1,
    }
    pending = command("led", "off", {})
    with patch.object(bridge, "_pending_commands", return_value=[pending]), \
        patch.object(bridge, "_mark_executing"), \
        patch.object(bridge, "_report_outcome_unknown") as unknown, \
        patch.object(bridge, "refresh_actuator_states"), \
        patch.object(bridge, "fetch_json", return_value={"unexpected": True}) as fetch:
        bridge.process_pending_actuator_commands(config)
    fetch.assert_called_once()
    unknown.assert_called_once()


def test_pre_dispatch_pump_status_failure_remains_confirmed_failed():
    config = {
        "esp32_data_url": "http://192.168.1.50/data",
        "aqualogic_backend_url": "https://api.example/api",
        "device_key": "key",
        "timeout_seconds": 1,
        "pump_manual_test_enabled": True,
    }
    pending = command("pump_a", "dispense", {})
    with patch.object(bridge, "_pending_commands", return_value=[pending]), \
        patch.object(bridge, "_mark_executing"), \
        patch.object(bridge, "_report_failed") as failed, \
        patch.object(bridge, "_report_outcome_unknown") as unknown, \
        patch.object(bridge, "fetch_json", side_effect=bridge.URLError("status unavailable")) as fetch:
        assert bridge.process_pending_actuator_commands(config) == 0
    assert fetch.call_args_list[0].args[0] == "http://192.168.1.50/syringeA/status"
    failed.assert_called_once()
    unknown.assert_not_called()


def test_explicit_firmware_client_rejection_remains_confirmed_failed():
    config = {
        "esp32_data_url": "http://192.168.1.50/data",
        "aqualogic_backend_url": "https://api.example/api",
        "device_key": "key",
        "timeout_seconds": 1,
    }
    pending = command("led", "off", {})
    rejection = bridge.HTTPError("http://192.168.1.50/led/off", 400, "rejected", {}, None)
    with patch.object(bridge, "_pending_commands", return_value=[pending]), \
        patch.object(bridge, "_mark_executing"), \
        patch.object(bridge, "_report_failed") as failed, \
        patch.object(bridge, "_report_outcome_unknown") as unknown, \
        patch.object(bridge, "refresh_actuator_states"), \
        patch.object(bridge, "fetch_json", side_effect=rejection):
        assert bridge.process_pending_actuator_commands(config) == 0
    failed.assert_called_once()
    unknown.assert_not_called()


def test_config_rejects_public_esp32_address(tmp_path):
    path = tmp_path / "bridge-config.json"
    path.write_text(json.dumps({
        "esp32_data_url": "http://8.8.8.8/data",
        "aqualogic_backend_url": "https://api.example/api",
        "device_key": "key",
    }))
    with pytest.raises(bridge.BridgeError, match="private"):
        bridge.load_config(path)


def backlog_record(seq, temperature=26.0, ph=7.1, turbidity=1.2, tds=220.0):
    return {
        "seq": seq,
        "temp_c": temperature,
        "ph_value": ph,
        "ph_status": "ok",
        "turbidity_ntu": turbidity,
        "turbidity_status": "ok",
        "tds_ppm": tds,
        "tds_status": "ok",
        "overall_status": "ok",
    }


def drain_config():
    return {
        "esp32_data_url": "http://192.168.1.50/data",
        "aqualogic_backend_url": "https://api.example/api",
        "device_key": "key",
        "timeout_seconds": 1,
    }


def zero_backlog_count():
    return {"pending": 0, "dropped": 0, "oldest_seq": 0, "newest_seq": 0}


def test_fetch_backlog_count_rejects_invalid_shape():
    config = drain_config()
    with patch.object(bridge, "fetch_json", return_value={"pending": 1}), \
        pytest.raises(bridge.BridgeError, match="backlog count"):
        bridge.fetch_backlog_count(config)


def test_drain_skips_when_nothing_is_pending():
    config = drain_config()
    with patch.object(bridge, "fetch_backlog_count", return_value=zero_backlog_count()) as count, \
        patch.object(bridge, "fetch_backlog_batch") as fetch, \
        patch.object(bridge, "post_reading") as submit, \
        patch.object(bridge, "_ack_backlog") as ack:
        assert bridge.drain_backlog(config) == 0
    count.assert_called_once_with(config)
    fetch.assert_not_called()
    submit.assert_not_called()
    ack.assert_not_called()


def test_drain_forwards_and_acks_each_batch():
    config = drain_config()
    first_batch = [backlog_record(1), backlog_record(2)]
    second_batch = [backlog_record(3)]
    with patch.object(bridge, "fetch_backlog_count", return_value={"pending": 3, "dropped": 0, "oldest_seq": 1, "newest_seq": 3}) as count, \
        patch.object(bridge, "BACKLOG_BATCH_LIMIT", 2), \
        patch.object(bridge, "fetch_backlog_batch", side_effect=[first_batch, second_batch, []]) as fetch, \
        patch.object(bridge, "post_reading") as submit, \
        patch.object(bridge, "_ack_backlog") as ack:
        assert bridge.drain_backlog(config) == 3
    count.assert_called_once_with(config)
    assert [call.args[0] for call in fetch.call_args_list] == [config, config]
    assert submit.call_count == 3
    assert [set(x.args[2]) for x in submit.call_args_list] == [
        {"temperature", "ph", "turbidity", "tds", "observed_at"}] * 3
    assert [x.args[2]["temperature"] for x in submit.call_args_list] == [26.0, 26.0, 26.0]
    assert [call.args for call in ack.call_args_list] == [(config, 2), (config, 3)]


def test_drain_forwards_a_small_backlog_in_one_batch():
    config = drain_config()
    batch = [backlog_record(1), backlog_record(2), backlog_record(3)]
    with patch.object(bridge, "fetch_backlog_count", return_value={"pending": 3, "dropped": 0, "oldest_seq": 1, "newest_seq": 3}), \
        patch.object(bridge, "fetch_backlog_batch", side_effect=[batch, []]), \
        patch.object(bridge, "post_reading"), \
        patch.object(bridge, "_ack_backlog") as ack:
        assert bridge.drain_backlog(config) == 3
    assert [call.args for call in ack.call_args_list] == [(config, 3)]


def test_drain_does_not_ack_when_first_forward_fails():
    config = drain_config()
    batch = [backlog_record(1), backlog_record(2)]
    with patch.object(bridge, "fetch_backlog_count", return_value={"pending": 2, "dropped": 0, "oldest_seq": 1, "newest_seq": 2}), \
        patch.object(bridge, "fetch_backlog_batch", side_effect=[batch, []]), \
        patch.object(bridge, "post_reading", side_effect=bridge.URLError("offline")), \
        patch.object(bridge, "_ack_backlog") as ack:
        assert bridge.drain_backlog(config) == 0
    ack.assert_not_called()


def test_drain_acks_confirmed_prefix_on_partial_batch_failure():
    config = drain_config()
    batch = [backlog_record(1), backlog_record(2), backlog_record(3)]
    with patch.object(bridge, "fetch_backlog_count", return_value={"pending": 3, "dropped": 0, "oldest_seq": 1, "newest_seq": 3}), \
        patch.object(bridge, "fetch_backlog_batch", side_effect=[batch, []]), \
        patch.object(bridge, "post_reading", side_effect=[None, None, bridge.URLError("offline")]), \
        patch.object(bridge, "_ack_backlog") as ack:
        assert bridge.drain_backlog(config) == 2
    assert [call.args for call in ack.call_args_list] == [(config, 2)]


def test_drain_stops_at_per_cycle_cap():
    config = drain_config()
    batches = [[backlog_record(seq)] for seq in range(1, 11)]
    with patch.object(bridge, "fetch_backlog_count", return_value={"pending": 10, "dropped": 0, "oldest_seq": 1, "newest_seq": 10}), \
        patch.object(bridge, "BACKLOG_MAX_PER_CYCLE", 3), \
        patch.object(bridge, "BACKLOG_BATCH_LIMIT", 1), \
        patch.object(bridge, "fetch_backlog_batch", side_effect=batches), \
        patch.object(bridge, "post_reading"), \
        patch.object(bridge, "_ack_backlog") as ack:
        assert bridge.drain_backlog(config) == 3
    assert [call.args for call in ack.call_args_list] == [(config, 1), (config, 2), (config, 3)]


def test_drain_estimates_observed_at_by_even_spread():
    config = drain_config()
    batch = [backlog_record(1), backlog_record(2), backlog_record(3)]
    before = datetime.now(timezone.utc)
    bridge._last_live_reading_at = before - timedelta(seconds=60)
    with patch.object(bridge, "fetch_backlog_count", return_value={"pending": 3, "dropped": 0, "oldest_seq": 1, "newest_seq": 3}), \
        patch.object(bridge, "fetch_backlog_batch", side_effect=[batch, []]), \
        patch.object(bridge, "post_reading") as submit, \
        patch.object(bridge, "_ack_backlog"):
        assert bridge.drain_backlog(config) == 3
    after = datetime.now(timezone.utc)
    stamps = [datetime.fromisoformat(x.args[2]["observed_at"]) for x in submit.call_args_list]
    assert len(stamps) == 3
    assert stamps == sorted(stamps)
    assert bridge._last_live_reading_at < stamps[0] < before
    assert before <= stamps[-1] <= after
    step = stamps[1] - stamps[0]
    assert step > timedelta(seconds=5)
    assert abs((stamps[2] - stamps[1]) - step) < timedelta(seconds=1)


def test_drain_observed_at_survives_reboot_seq_jump():
    config = drain_config()
    # The ESP32 returns its buffer newest first, so after a reboot the oldest
    # batch can be a mix of the pre-reboot high seqs and post-reboot low seqs.
    batch = [backlog_record(100001), backlog_record(100002), backlog_record(1), backlog_record(2)]
    before = datetime.now(timezone.utc)
    bridge._last_live_reading_at = before - timedelta(seconds=60)
    with patch.object(bridge, "fetch_backlog_count", return_value={"pending": 4, "dropped": 0, "oldest_seq": 1, "newest_seq": 100002}), \
        patch.object(bridge, "fetch_backlog_batch", side_effect=[batch, []]), \
        patch.object(bridge, "post_reading") as submit, \
        patch.object(bridge, "_ack_backlog"):
        assert bridge.drain_backlog(config) == 4
    after = datetime.now(timezone.utc)
    stamps = dict(zip([100001, 100002, 1, 2], [datetime.fromisoformat(x.args[2]["observed_at"]) for x in submit.call_args_list]))
    assert bridge._last_live_reading_at < stamps[1] < stamps[2] < stamps[100001] < stamps[100002] <= after
    assert stamps[1] - bridge._last_live_reading_at < timedelta(seconds=1)


def test_drain_marks_estimates_but_strips_markers_at_the_wire(caplog):
    config = drain_config()
    batch = [backlog_record(1), backlog_record(2)]
    bridge._last_live_reading_at = datetime.now(timezone.utc) - timedelta(seconds=60)
    with caplog.at_level(logging.INFO, logger="aqualogic.bridge"), \
        patch.object(bridge, "fetch_backlog_count", return_value={"pending": 2, "dropped": 0, "oldest_seq": 1, "newest_seq": 2}), \
        patch.object(bridge, "fetch_backlog_batch", side_effect=[batch, []]), \
        patch.object(bridge, "post_reading") as submit, \
        patch.object(bridge, "_ack_backlog"):
        bridge.drain_backlog(config)
    assert "time_estimated=true" in caplog.text
    assert "even_spread" in caplog.text
    assert all(set(x.args[2]) == {"temperature", "ph", "turbidity", "tds", "observed_at"} for x in submit.call_args_list)


def test_drain_falls_back_to_poll_interval_window_without_anchor():
    config = drain_config()
    batch = [backlog_record(seq) for seq in range(1, 11)]
    before = datetime.now(timezone.utc)
    with patch.object(bridge, "fetch_backlog_count", return_value={"pending": 10, "dropped": 0, "oldest_seq": 1, "newest_seq": 10}), \
        patch.object(bridge, "fetch_backlog_batch", side_effect=[batch, []]), \
        patch.object(bridge, "post_reading") as submit, \
        patch.object(bridge, "_ack_backlog"):
        bridge.drain_backlog(config)
    stamps = [datetime.fromisoformat(x.args[2]["observed_at"]) for x in submit.call_args_list]
    assert len(stamps) == 10
    assert before - timedelta(seconds=150) <= stamps[0] <= before
    assert stamps[-1] <= datetime.now(timezone.utc)


def test_drain_updates_anchor_only_when_backlog_empties():
    config = drain_config()
    anchor = datetime.now(timezone.utc) - timedelta(seconds=60)
    bridge._last_live_reading_at = anchor
    batch = [backlog_record(1)]
    with patch.object(bridge, "fetch_backlog_count", return_value={"pending": 1, "dropped": 0, "oldest_seq": 1, "newest_seq": 1}), \
        patch.object(bridge, "fetch_backlog_batch", side_effect=[batch, []]), \
        patch.object(bridge, "post_reading"), \
        patch.object(bridge, "_ack_backlog"):
        bridge.drain_backlog(config)
    assert bridge._last_live_reading_at == anchor
    before = datetime.now(timezone.utc)
    with patch.object(bridge, "fetch_backlog_count", return_value=zero_backlog_count()), \
        patch.object(bridge, "fetch_backlog_batch"), \
        patch.object(bridge, "post_reading"), \
        patch.object(bridge, "_ack_backlog"):
        bridge.drain_backlog(config)
    assert bridge._last_live_reading_at is not None
    assert before - timedelta(seconds=1) <= bridge._last_live_reading_at <= datetime.now(timezone.utc)

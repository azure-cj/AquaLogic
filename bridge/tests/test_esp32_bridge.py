import json
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest.mock import patch

import pytest

sys.path.insert(0, str(Path(__file__).parents[1]))
import esp32_bridge as bridge


FIXTURE = Path(__file__).parents[2] / "backend" / "tests" / "fixtures" / "esp32_data.json"


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


def pump_status(*, active=False, dose_count=2, volume_ml=1.0):
    return {
        "active": active,
        "dose_count": dose_count,
        "last_dispensed": "12:34:56",
        "volume_ml": volume_ml,
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


def test_invalid_pump_safety_stop_reports_failure_without_retrying():
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
        patch.object(bridge, "_report_failed") as failed, \
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
    failed.assert_called_once()


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


def test_timeout_reports_failure_without_retrying_hardware():
    config = {
        "esp32_data_url": "http://192.168.1.50/data",
        "aqualogic_backend_url": "https://api.example/api",
        "device_key": "key",
        "timeout_seconds": 1,
    }
    pending = command("feeder", "feed_now", {})
    with patch.object(bridge, "_pending_commands", return_value=[pending]), \
        patch.object(bridge, "_mark_executing"), \
        patch.object(bridge, "_report_failed") as failed, \
        patch.object(bridge, "refresh_actuator_states"), \
        patch.object(bridge, "fetch_json", side_effect=bridge.URLError("offline")) as fetch:
        assert bridge.process_pending_actuator_commands(config) == 0
    fetch.assert_called_once_with("http://192.168.1.50/feeder/feed", 1.0)
    failed.assert_called_once()


def test_invalid_firmware_response_is_failed_without_a_second_request():
    config = {
        "esp32_data_url": "http://192.168.1.50/data",
        "aqualogic_backend_url": "https://api.example/api",
        "device_key": "key",
        "timeout_seconds": 1,
    }
    pending = command("led", "off", {})
    with patch.object(bridge, "_pending_commands", return_value=[pending]), \
        patch.object(bridge, "_mark_executing"), \
        patch.object(bridge, "_report_failed") as failed, \
        patch.object(bridge, "refresh_actuator_states"), \
        patch.object(bridge, "fetch_json", return_value={"unexpected": True}) as fetch:
        bridge.process_pending_actuator_commands(config)
    fetch.assert_called_once()
    failed.assert_called_once()


def test_config_rejects_public_esp32_address(tmp_path):
    path = tmp_path / "bridge-config.json"
    path.write_text(json.dumps({
        "esp32_data_url": "http://8.8.8.8/data",
        "aqualogic_backend_url": "https://api.example/api",
        "device_key": "key",
    }))
    with pytest.raises(bridge.BridgeError, match="private"):
        bridge.load_config(path)

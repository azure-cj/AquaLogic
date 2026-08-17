"""Temporary local bridge for ESP32 sensors and allowlisted actuators."""
from __future__ import annotations

import argparse
import ipaddress
import json
import logging
import math
import re
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode, urlsplit, urlunsplit
from urllib.request import Request, urlopen


LOG = logging.getLogger("aqualogic.bridge")
LIMITS = {"temperature": (-10, 60), "ph": (0, 14), "turbidity": (0, 3000), "tds": (0, 5000)}
FIELD_MAP = {"temp_c": "temperature", "ph_value": "ph", "turbidity_ntu": "turbidity", "tds_ppm": "tds"}
LIGHT_TIMER_MAX_MS = 86_400_000
FEEDER_ANGLE_MIN = 0
FEEDER_ANGLE_MAX = 180
FEEDER_DURATION_MIN_MS = 500
FEEDER_DURATION_MAX_MS = 60_000
FEEDER_SCHEDULE_SLOTS = 3
PUMP_COMPLETION_TIMEOUT_DEFAULT_SECONDS = 30
PUMP_COMPLETION_TIMEOUT_MIN_SECONDS = 5
PUMP_COMPLETION_TIMEOUT_MAX_SECONDS = 120
PUMP_STATUS_POLL_INTERVAL_SECONDS = 0.25
COMMAND_ID_PATTERN = re.compile(r"^[A-Za-z0-9_-]{1,64}$")
TIME_PATTERN = re.compile(r"^(?:[01]\d|2[0-3]):[0-5]\d$")
PUMP_ACTUATORS = {"pump_a", "pump_b"}


class BridgeError(ValueError):
    pass


def safe_error(error: BaseException) -> str:
    """Keep network/configuration details, keys, and URLs out of logs/results."""
    if isinstance(error, HTTPError):
        return f"HTTP {error.code}"
    if isinstance(error, URLError):
        return "network error"
    if isinstance(error, TimeoutError):
        return "timeout"
    if isinstance(error, OSError):
        return type(error).__name__
    return str(error)


def _is_number(value: object) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def _is_int(value: object) -> bool:
    return isinstance(value, int) and not isinstance(value, bool)


def _require_keys(payload: dict[str, Any], expected: set[str], label: str) -> None:
    if set(payload) != expected:
        raise BridgeError(f"{label} must contain exactly: {', '.join(sorted(expected))}")


def _validate_time(value: object, label: str) -> str:
    if not isinstance(value, str) or TIME_PATTERN.fullmatch(value) is None:
        raise BridgeError(f"{label} must use HH:MM in the 24-hour clock")
    return value


def _split_time(value: str, label: str) -> tuple[str, str]:
    _validate_time(value, label)
    hour, minute = value.split(":")
    return hour, minute


def translate_esp32_payload(payload: object) -> dict[str, float]:
    if not isinstance(payload, dict):
        raise BridgeError("ESP32 response must be a JSON object")
    translated: dict[str, float] = {}
    for source, target in FIELD_MAP.items():
        value = payload.get(source)
        if not _is_number(value):
            raise BridgeError(f"ESP32 field {source!r} must be a finite number")
        minimum, maximum = LIMITS[target]
        if not minimum <= value <= maximum:
            raise BridgeError(f"ESP32 field {source!r} is outside the accepted range")
        translated[target] = float(value)
    translated["observed_at"] = datetime.now(timezone.utc).isoformat()
    return translated


def _parse_expiry(value: object) -> datetime:
    if not isinstance(value, str):
        raise BridgeError("Actuator command expiry is missing or invalid")
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as error:
        raise BridgeError("Actuator command expiry is invalid") from error
    return parsed.replace(tzinfo=timezone.utc) if parsed.tzinfo is None else parsed


def _validate_command_payload(actuator: str, action: str, payload: object) -> dict[str, Any]:
    if not isinstance(payload, dict):
        raise BridgeError("Actuator command payload must be a JSON object")

    if actuator in PUMP_ACTUATORS:
        if action == "dispense":
            if payload:
                raise BridgeError(f"{actuator} dispense uses the firmware-configured volume and does not accept a payload")
            return {}
        if action in {"stop", "retract"}:
            if payload:
                raise BridgeError(f"{actuator}/{action} does not accept a payload")
            return {}
        raise BridgeError(f"Actuator action {actuator}/{action} is not allowlisted")

    if action in {"on", "off", "feed_now"}:
        if payload:
            raise BridgeError(f"{actuator}/{action} does not accept a payload")
        return {}

    if action == "timer" and actuator in {"uv", "led"}:
        _require_keys(payload, {"duration_ms"}, f"{actuator} timer payload")
        duration = payload["duration_ms"]
        if not _is_int(duration) or not 1 <= duration <= LIGHT_TIMER_MAX_MS:
            raise BridgeError("Light timer duration is outside the accepted range")
        return {"duration_ms": duration}

    if action == "schedule" and actuator in {"uv", "led"}:
        _require_keys(payload, {"enabled", "on_time", "off_time"}, f"{actuator} schedule payload")
        if not isinstance(payload["enabled"], bool):
            raise BridgeError("Light schedule enabled must be boolean")
        on_time = _validate_time(payload["on_time"], "Light schedule on_time")
        off_time = _validate_time(payload["off_time"], "Light schedule off_time")
        return {"enabled": payload["enabled"], "on_time": on_time, "off_time": off_time}

    if actuator == "feeder" and action == "config":
        _require_keys(payload, {"open_angle", "duration_ms"}, "Feeder config payload")
        angle = payload["open_angle"]
        duration = payload["duration_ms"]
        if not _is_int(angle) or not FEEDER_ANGLE_MIN <= angle <= FEEDER_ANGLE_MAX:
            raise BridgeError("Feeder open angle is outside the firmware-supported range")
        if not _is_int(duration) or not FEEDER_DURATION_MIN_MS <= duration <= FEEDER_DURATION_MAX_MS:
            raise BridgeError("Feeder duration is outside the firmware-supported range")
        return {"open_angle": angle, "duration_ms": duration}

    if actuator == "feeder" and action == "schedule":
        _require_keys(payload, {"slots"}, "Feeder schedule payload")
        slots = payload["slots"]
        if not isinstance(slots, list) or len(slots) != FEEDER_SCHEDULE_SLOTS:
            raise BridgeError("Feeder schedule must contain exactly three slots")
        normalized_slots = []
        for index, slot in enumerate(slots):
            if not isinstance(slot, dict):
                raise BridgeError(f"Feeder schedule slot {index} must be an object")
            _require_keys(slot, {"enabled", "time"}, f"Feeder schedule slot {index}")
            if not isinstance(slot["enabled"], bool):
                raise BridgeError(f"Feeder schedule slot {index} enabled must be boolean")
            normalized_slots.append({"enabled": slot["enabled"], "time": _validate_time(slot["time"], f"Feeder schedule slot {index} time")})
        return {"slots": normalized_slots}

    raise BridgeError(f"Actuator action {actuator}/{action} is not allowlisted")


def validate_pending_command(command: object) -> dict[str, Any]:
    if not isinstance(command, dict):
        raise BridgeError("Pending actuator command must be a JSON object")
    command_id = command.get("command_id")
    actuator = command.get("actuator")
    action = command.get("action")
    if not isinstance(command_id, str) or COMMAND_ID_PATTERN.fullmatch(command_id) is None:
        raise BridgeError("Actuator command ID is invalid")
    if not isinstance(actuator, str) or actuator not in {"uv", "led", "feeder", "pump_a", "pump_b"} or not isinstance(action, str):
        raise BridgeError("Actuator command target is not allowlisted")
    expires_at = _parse_expiry(command.get("expires_at"))
    if expires_at <= datetime.now(timezone.utc):
        raise BridgeError("Actuator command is expired")
    payload = _validate_command_payload(actuator, action, command.get("payload"))
    return {
        "command_id": command_id,
        "device_id": command.get("device_id"),
        "actuator": actuator,
        "action": action,
        "payload": payload,
        "expires_at": expires_at,
    }


def translate_actuator_command(command: object) -> dict[str, Any]:
    """Translate one validated backend command to an exact firmware GET route."""
    validated = validate_pending_command(command)
    actuator = validated["actuator"]
    action = validated["action"]
    payload = validated["payload"]
    if actuator in {"uv", "led"}:
        prefix = "/uv" if actuator == "uv" else "/led"
        if action in {"on", "off"}:
            path = f"{prefix}/{action}"
            query: dict[str, str] = {}
            expected = {"led": action}
        elif action == "timer":
            path = f"{prefix}/timer"
            query = {"duration": str(payload["duration_ms"])}
            expected = {"led": "timer"}
        else:
            on_hour, on_minute = _split_time(payload["on_time"], "schedule on_time")
            off_hour, off_minute = _split_time(payload["off_time"], "schedule off_time")
            path = f"{prefix}/schedule"
            query = {
                "enabled": "1" if payload["enabled"] else "0",
                "onH": on_hour,
                "onM": on_minute,
                "offH": off_hour,
                "offM": off_minute,
            }
            expected = {"schedule": "saved"}
    elif actuator in PUMP_ACTUATORS:
        prefix = "/syringeA" if actuator == "pump_a" else "/syringeB"
        path = f"{prefix}/{action}"
        query = {}
        expected = {
            "dispense": {"dispensed": True},
            "stop": {"stopped": True},
            "retract": {"retracted": True},
        }[action]
    elif action == "feed_now":
        path = "/feeder/feed"
        query = {}
        expected = {"fed": True}
    elif action == "config":
        path = "/feeder/config"
        query = {"angle": str(payload["open_angle"]), "duration": str(payload["duration_ms"])}
        expected = {"config": "saved"}
    else:
        path = "/feeder/schedule"
        query = {}
        for index, slot in enumerate(payload["slots"]):
            hour, minute = _split_time(slot["time"], f"Feeder schedule slot {index} time")
            query.update({f"h{index}": hour, f"m{index}": minute, f"e{index}": "1" if slot["enabled"] else "0"})
        expected = {"schedule": "saved"}
    return {
        "command_id": validated["command_id"],
        "actuator": actuator,
        "action": action,
        "path": path,
        "query": query,
        "expected": expected,
    }


def _translate_light_status(payload: object) -> dict[str, Any]:
    if not isinstance(payload, dict):
        raise BridgeError("ESP32 light status must be a JSON object")
    required = {"led_on", "remaining_ms", "total_on_ms", "schedule_enabled", "sched_on", "sched_off"}
    _require_keys(payload, required, "ESP32 light status")
    if not isinstance(payload["led_on"], bool) or not _is_int(payload["remaining_ms"]) or not 0 <= payload["remaining_ms"] <= LIGHT_TIMER_MAX_MS:
        raise BridgeError("ESP32 light status contains an invalid timer state")
    if not _is_int(payload["total_on_ms"]) or not 0 <= payload["total_on_ms"] <= 4_294_967_295:
        raise BridgeError("ESP32 light status contains an invalid total-on value")
    if not isinstance(payload["schedule_enabled"], bool):
        raise BridgeError("ESP32 light status contains an invalid schedule flag")
    return {
        "on": payload["led_on"],
        "remaining_ms": payload["remaining_ms"],
        "total_on_ms": payload["total_on_ms"],
        "schedule_enabled": payload["schedule_enabled"],
        "on_time": _validate_time(payload["sched_on"], "ESP32 light schedule on time"),
        "off_time": _validate_time(payload["sched_off"], "ESP32 light schedule off time"),
    }


def _translate_feeder_status(payload: object) -> dict[str, Any]:
    if not isinstance(payload, dict):
        raise BridgeError("ESP32 feeder status must be a JSON object")
    required = {"feeding", "feed_count", "last_fed", "open_angle", "duration_ms", "schedule"}
    _require_keys(payload, required, "ESP32 feeder status")
    if not isinstance(payload["feeding"], bool) or not _is_int(payload["feed_count"]) or payload["feed_count"] < 0:
        raise BridgeError("ESP32 feeder status contains an invalid activity state")
    if not isinstance(payload["last_fed"], str) or len(payload["last_fed"]) > 80:
        raise BridgeError("ESP32 feeder status contains an invalid last-fed value")
    if not _is_int(payload["open_angle"]) or not FEEDER_ANGLE_MIN <= payload["open_angle"] <= FEEDER_ANGLE_MAX:
        raise BridgeError("ESP32 feeder status contains an invalid angle")
    if not _is_int(payload["duration_ms"]) or not FEEDER_DURATION_MIN_MS <= payload["duration_ms"] <= FEEDER_DURATION_MAX_MS:
        raise BridgeError("ESP32 feeder status contains an invalid duration")
    schedule = payload["schedule"]
    if not isinstance(schedule, list) or len(schedule) != FEEDER_SCHEDULE_SLOTS:
        raise BridgeError("ESP32 feeder status must contain exactly three schedule slots")
    normalized_schedule = []
    for index, slot in enumerate(schedule):
        if not isinstance(slot, dict) or set(slot) != {"hour", "minute", "enabled"}:
            raise BridgeError(f"ESP32 feeder schedule slot {index} is invalid")
        if not _is_int(slot["hour"]) or not 0 <= slot["hour"] <= 23 or not _is_int(slot["minute"]) or not 0 <= slot["minute"] <= 59 or not isinstance(slot["enabled"], bool):
            raise BridgeError(f"ESP32 feeder schedule slot {index} is invalid")
        normalized_schedule.append({"enabled": slot["enabled"], "time": f"{slot['hour']:02d}:{slot['minute']:02d}"})
    return {
        "feeding": payload["feeding"],
        "feed_count": payload["feed_count"],
        "last_fed": payload["last_fed"],
        "open_angle": payload["open_angle"],
        "duration_ms": payload["duration_ms"],
        "schedule": normalized_schedule,
    }


def _translate_pump_status(payload: object) -> dict[str, Any]:
    if not isinstance(payload, dict):
        raise BridgeError("ESP32 pump status must be a JSON object")
    required = {"active", "dose_count", "last_dispensed", "volume_ml", "schedule"}
    _require_keys(payload, required, "ESP32 pump status")
    if not isinstance(payload["active"], bool) or not _is_int(payload["dose_count"]) or not 0 <= payload["dose_count"] <= 2_147_483_647:
        raise BridgeError("ESP32 pump status contains an invalid activity or dose count")
    if not isinstance(payload["last_dispensed"], str) or len(payload["last_dispensed"]) > 80:
        raise BridgeError("ESP32 pump status contains an invalid last-dispensed value")
    if not _is_number(payload["volume_ml"]) or not 0 <= payload["volume_ml"] <= 100:
        raise BridgeError("ESP32 pump status contains an invalid volume")
    schedule = payload["schedule"]
    if not isinstance(schedule, list) or len(schedule) != FEEDER_SCHEDULE_SLOTS:
        raise BridgeError("ESP32 pump status must contain exactly three schedule slots")
    for index, slot in enumerate(schedule):
        if not isinstance(slot, dict) or set(slot) != {"hour", "minute", "enabled"}:
            raise BridgeError(f"ESP32 pump schedule slot {index} is invalid")
        if (
            not _is_int(slot["hour"])
            or not 0 <= slot["hour"] <= 23
            or not _is_int(slot["minute"])
            or not 0 <= slot["minute"] <= 59
            or not isinstance(slot["enabled"], bool)
        ):
            raise BridgeError(f"ESP32 pump schedule slot {index} is invalid")
    return {
        "active": payload["active"],
        "dose_count": payload["dose_count"],
        "last_dispensed": payload["last_dispensed"],
        "volume_ml": float(payload["volume_ml"]),
    }


def fetch_json(url: str, timeout: float, headers: dict[str, str] | None = None) -> object:
    request_headers = {"Accept": "application/json", **(headers or {})}
    request = Request(url, headers=request_headers, method="GET")
    with urlopen(request, timeout=timeout) as response:  # nosec B310: URL is deliberate bridge configuration
        if response.status != 200:
            raise BridgeError(f"Remote endpoint returned HTTP {response.status}")
        try:
            return json.loads(response.read().decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise BridgeError("Remote endpoint returned invalid JSON") from error


def _post_json(url: str, headers: dict[str, str], payload: dict[str, Any], timeout: float) -> object:
    body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
    request = Request(
        url,
        data=body,
        headers={"Content-Type": "application/json", "Accept": "application/json", **headers},
        method="POST",
    )
    with urlopen(request, timeout=timeout) as response:  # nosec B310: backend URL is deliberate bridge configuration
        if response.status not in (200, 201):
            raise BridgeError(f"AquaLogic returned HTTP {response.status}")
        try:
            return json.loads(response.read().decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise BridgeError("AquaLogic returned invalid JSON") from error


def post_reading(url: str, device_key: str, payload: dict[str, float], timeout: float) -> None:
    response = _post_json(
        url.rstrip("/") + "/device-ingestion/readings",
        {"X-Device-Key": device_key},
        payload,
        timeout,
    )
    if not isinstance(response, dict) or not isinstance(response.get("id"), int):
        raise BridgeError("AquaLogic returned an invalid sensor-ingestion response")


def _backend_url(config: dict, path: str) -> str:
    return config["aqualogic_backend_url"].rstrip("/") + path


def _esp32_url(config: dict, path: str, query: dict[str, str] | None = None) -> str:
    parsed = urlsplit(config["esp32_data_url"])
    return urlunsplit((parsed.scheme, parsed.netloc, path, urlencode(query or {}), ""))


def _device_headers(config: dict) -> dict[str, str]:
    return {"X-Device-Key": config["device_key"]}


def _pending_commands(config: dict) -> list[object]:
    response = fetch_json(
        _backend_url(config, "/device-ingestion/actuators/pending"),
        float(config["timeout_seconds"]),
        _device_headers(config),
    )
    if not isinstance(response, list):
        raise BridgeError("AquaLogic returned an invalid pending-command response")
    return response


def _mark_executing(config: dict, command_id: str) -> None:
    response = _post_json(
        _backend_url(config, f"/device-ingestion/actuators/{command_id}/executing"),
        _device_headers(config),
        {},
        float(config["timeout_seconds"]),
    )
    if not isinstance(response, dict) or response.get("status") != "executing":
        raise BridgeError("AquaLogic returned an invalid executing acknowledgement")


def _report_succeeded(config: dict, command_id: str, result: dict[str, Any]) -> None:
    response = _post_json(
        _backend_url(config, f"/device-ingestion/actuators/{command_id}/succeeded"),
        _device_headers(config),
        {"result": result},
        float(config["timeout_seconds"]),
    )
    if not isinstance(response, dict) or response.get("status") != "succeeded":
        raise BridgeError("AquaLogic returned an invalid success acknowledgement")


def _report_failed(config: dict, command_id: str, error: str) -> None:
    response = _post_json(
        _backend_url(config, f"/device-ingestion/actuators/{command_id}/failed"),
        _device_headers(config),
        {"error": error[:500]},
        float(config["timeout_seconds"]),
    )
    if not isinstance(response, dict) or response.get("status") != "failed":
        raise BridgeError("AquaLogic returned an invalid failure acknowledgement")


def report_actuator_state(config: dict, actuator: str, state: dict[str, Any], command_id: str | None = None) -> None:
    response = _post_json(
        _backend_url(config, "/device-ingestion/actuator-state"),
        _device_headers(config),
        {"actuator": actuator, "state": state, **({"command_id": command_id} if command_id else {})},
        float(config["timeout_seconds"]),
    )
    if not isinstance(response, dict) or response.get("actuator") != actuator:
        raise BridgeError("AquaLogic returned an invalid actuator-state acknowledgement")


def refresh_actuator_states(config: dict, command_id: str | None = None) -> None:
    status_paths = {
        "uv": "/uv/status",
        "led": "/led/status",
        "feeder": "/feeder/status",
        "pump_a": "/syringeA/status",
        "pump_b": "/syringeB/status",
    }
    for actuator, path in status_paths.items():
        try:
            raw = fetch_json(_esp32_url(config, path), float(config["timeout_seconds"]))
            if actuator == "feeder":
                state = _translate_feeder_status(raw)
            elif actuator in PUMP_ACTUATORS:
                state = _translate_pump_status(raw)
            else:
                state = _translate_light_status(raw)
            report_actuator_state(config, actuator, state, command_id=command_id)
        except (BridgeError, HTTPError, URLError, TimeoutError, OSError) as error:
            LOG.warning("Actuator state refresh failed for %s (%s)", actuator, safe_error(error))


def _pump_status_path(actuator: str) -> str:
    if actuator not in PUMP_ACTUATORS:
        raise BridgeError("Actuator is not a syringe pump")
    return "/syringeA/status" if actuator == "pump_a" else "/syringeB/status"


def _pump_stop_path(actuator: str) -> str:
    if actuator not in PUMP_ACTUATORS:
        raise BridgeError("Actuator is not a syringe pump")
    return "/syringeA/stop" if actuator == "pump_a" else "/syringeB/stop"


def _read_pump_statuses(config: dict) -> dict[str, dict[str, Any]]:
    statuses: dict[str, dict[str, Any]] = {}
    for actuator in sorted(PUMP_ACTUATORS):
        raw = fetch_json(
            _esp32_url(config, _pump_status_path(actuator)),
            float(config["timeout_seconds"]),
        )
        statuses[actuator] = _translate_pump_status(raw)
    return statuses


def _stop_pump_once(config: dict, actuator: str) -> dict[str, Any]:
    stop_path = _pump_stop_path(actuator)
    stop_response = fetch_json(
        _esp32_url(config, stop_path),
        float(config["timeout_seconds"]),
    )
    if stop_response != {"stopped": True}:
        raise BridgeError("ESP32 returned an invalid pump safety-stop response")
    return {"path": stop_path, "response": stop_response}


def _wait_for_configured_pump_dose(
    config: dict,
    actuator: str,
    initial_status: dict[str, Any],
) -> dict[str, Any]:
    """Wait for the firmware's configured volume move, never re-triggering it."""
    started_at = time.monotonic()
    timeout_seconds = float(config.get("pump_completion_timeout_seconds", PUMP_COMPLETION_TIMEOUT_DEFAULT_SECONDS))
    deadline = started_at + timeout_seconds
    saw_active = False

    while True:
        raw = fetch_json(
            _esp32_url(config, _pump_status_path(actuator)),
            float(config["timeout_seconds"]),
        )
        current_status = _translate_pump_status(raw)
        if current_status["active"]:
            saw_active = True

        dose_started = current_status["dose_count"] > initial_status["dose_count"]
        if not current_status["active"] and (saw_active or dose_started):
            return {
                "configured_volume_ml": current_status["volume_ml"],
                "completion_observed": True,
                "elapsed_ms": round((time.monotonic() - started_at) * 1000),
            }

        if time.monotonic() >= deadline:
            raise BridgeError("Pump configured-volume dispense did not complete before the safety timeout")
        time.sleep(PUMP_STATUS_POLL_INTERVAL_SECONDS)


def _execute_translated_command(config: dict, translated: dict[str, Any]) -> dict[str, Any]:
    """Make one allowlisted physical call without reissuing ambiguous commands."""
    initial_pump_status: dict[str, Any] | None = None
    if translated["actuator"] in PUMP_ACTUATORS and translated["action"] == "dispense":
        pump_statuses = _read_pump_statuses(config)
        if any(status["active"] for status in pump_statuses.values()):
            raise BridgeError("A syringe pump is already active; dispense was not started")
        initial_pump_status = pump_statuses[translated["actuator"]]

    raw_response = fetch_json(
        _esp32_url(config, translated["path"], translated["query"]),
        float(config["timeout_seconds"]),
    )
    if raw_response != translated["expected"]:
        raise BridgeError("ESP32 returned an invalid actuator response")

    result: dict[str, Any] = {"path": translated["path"], "response": raw_response}
    if translated["actuator"] in PUMP_ACTUATORS and translated["action"] == "dispense":
        try:
            result.update(_wait_for_configured_pump_dose(config, translated["actuator"], initial_pump_status or {}))
        except (BridgeError, HTTPError, URLError, TimeoutError, OSError) as error:
            # A stop is an intentional one-shot safety action after a
            # physical dispense has started. It is never a retry of dispense.
            result["safety_stop"] = _stop_pump_once(config, translated["actuator"])
            raise error
    return result


def process_pending_actuator_commands(config: dict) -> int:
    pending = _pending_commands(config)
    processed = 0
    for raw_command in pending:
        command_id = raw_command.get("command_id") if isinstance(raw_command, dict) else "unknown"
        try:
            translated = translate_actuator_command(raw_command)
        except BridgeError as error:
            # Invalid commands are never sent to the ESP32. Claiming then failing
            # the row leaves a safe audit trail and prevents a bad row from being
            # delivered forever; it does not retry a physical operation.
            if isinstance(command_id, str) and COMMAND_ID_PATTERN.fullmatch(command_id):
                try:
                    _mark_executing(config, command_id)
                    _report_failed(config, command_id, f"Bridge validation failed: {error}")
                except (BridgeError, HTTPError, URLError, TimeoutError, OSError) as report_error:
                    LOG.warning("Could not report invalid actuator command %s: %s", command_id, safe_error(report_error))
            else:
                LOG.warning("Ignored invalid actuator command: %s", safe_error(error))
            continue

        try:
            _mark_executing(config, translated["command_id"])
        except HTTPError as error:
            if error.code == 409:
                LOG.info("Actuator command %s was already claimed or finalized", translated["command_id"])
                continue
            raise
        except (BridgeError, URLError, TimeoutError, OSError):
            raise

        if translated["actuator"] in PUMP_ACTUATORS and not config.get("pump_manual_test_enabled", False):
            try:
                _report_failed(config, translated["command_id"], "Pump manual testing is disabled in bridge configuration")
            except (BridgeError, HTTPError, URLError, TimeoutError, OSError) as report_error:
                LOG.warning("Could not report disabled pump command %s: %s", translated["command_id"], safe_error(report_error))
            LOG.warning("Rejected pump command %s because manual testing is disabled", translated["command_id"])
            continue

        try:
            result = _execute_translated_command(config, translated)
        except (BridgeError, HTTPError, URLError, TimeoutError, OSError) as error:
            # A timeout may mean a physical request already ran, so the bridge
            # reports failure and never retries any hardware request. Pump
            # dispense additionally has one intentional safety-stop request.
            try:
                _report_failed(config, translated["command_id"], safe_error(error))
            except (BridgeError, HTTPError, URLError, TimeoutError, OSError) as report_error:
                LOG.warning("Could not report failed actuator command %s: %s", translated["command_id"], safe_error(report_error))
            try:
                refresh_actuator_states(config, command_id=translated["command_id"])
            except (BridgeError, HTTPError, URLError, TimeoutError, OSError) as refresh_error:
                LOG.warning("Could not refresh state after failed actuator command %s: %s", translated["command_id"], safe_error(refresh_error))
            LOG.warning("Actuator command %s failed: %s", translated["command_id"], safe_error(error))
            continue

        try:
            refresh_actuator_states(config, command_id=translated["command_id"])
            result["state_refresh"] = "attempted"
        except (BridgeError, HTTPError, URLError, TimeoutError, OSError) as error:
            # State refresh is best effort; the physical command already
            # returned success and must not be reissued.
            result["state_refresh_error"] = safe_error(error)
        try:
            _report_succeeded(config, translated["command_id"], result)
        except (BridgeError, HTTPError, URLError, TimeoutError, OSError) as error:
            LOG.warning("Could not report successful actuator command %s: %s", translated["command_id"], safe_error(error))
        processed += 1
    return processed


def load_config(path: Path) -> dict:
    try:
        config = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise BridgeError(f"Could not read configuration: {type(error).__name__}") from error
    if not isinstance(config, dict):
        raise BridgeError("Bridge configuration must be a JSON object")
    required = ("esp32_data_url", "aqualogic_backend_url", "device_key")
    missing = [key for key in required if not isinstance(config.get(key), str) or not config[key].strip()]
    if missing:
        raise BridgeError("Missing configuration values: " + ", ".join(missing))
    config.setdefault("poll_interval_seconds", 15)
    config.setdefault("timeout_seconds", 5)
    config.setdefault("actuator_enabled", True)
    config.setdefault("pump_manual_test_enabled", False)
    config.setdefault("pump_completion_timeout_seconds", PUMP_COMPLETION_TIMEOUT_DEFAULT_SECONDS)
    numeric_keys = ("poll_interval_seconds", "timeout_seconds")
    if any(isinstance(config[key], bool) or not isinstance(config[key], (int, float)) or config[key] <= 0 for key in numeric_keys):
        raise BridgeError("Polling interval and timeout must be positive")
    if not isinstance(config["actuator_enabled"], bool):
        raise BridgeError("actuator_enabled must be boolean")
    if not isinstance(config["pump_manual_test_enabled"], bool):
        raise BridgeError("pump_manual_test_enabled must be boolean")
    completion_timeout = config["pump_completion_timeout_seconds"]
    if (
        isinstance(completion_timeout, bool)
        or not isinstance(completion_timeout, (int, float))
        or not PUMP_COMPLETION_TIMEOUT_MIN_SECONDS <= completion_timeout <= PUMP_COMPLETION_TIMEOUT_MAX_SECONDS
    ):
        raise BridgeError(
            f"pump_completion_timeout_seconds must be between {PUMP_COMPLETION_TIMEOUT_MIN_SECONDS} and "
            f"{PUMP_COMPLETION_TIMEOUT_MAX_SECONDS}"
        )
    _validate_private_esp32_url(config["esp32_data_url"])
    _validate_backend_url(config["aqualogic_backend_url"])
    return config


def _validate_private_esp32_url(url: str) -> None:
    parsed = urlsplit(url)
    if parsed.scheme != "http" or not parsed.hostname or parsed.path.rstrip("/") != "/data":
        raise BridgeError("esp32_data_url must be a local HTTP URL ending in /data")
    host = parsed.hostname.lower()
    try:
        address = ipaddress.ip_address(host)
    except ValueError:
        if host not in {"localhost", "esp32"} and not host.endswith(".local"):
            raise BridgeError("esp32_data_url must use a private IP, localhost, or a .local host")
        return
    if not (address.is_private or address.is_loopback or address.is_link_local):
        raise BridgeError("esp32_data_url must use a private local-network address")


def _validate_backend_url(url: str) -> None:
    parsed = urlsplit(url)
    if not parsed.hostname or parsed.scheme not in {"http", "https"}:
        raise BridgeError("aqualogic_backend_url must be an HTTP(S) URL")
    if parsed.scheme == "http":
        try:
            address = ipaddress.ip_address(parsed.hostname)
        except ValueError:
            address = None
        if parsed.hostname not in {"localhost", "127.0.0.1", "::1"} and not (address and address.is_loopback):
            raise BridgeError("Remote AquaLogic backend URLs must use HTTPS")


def poll_sensor_once(config: dict) -> None:
    payload = translate_esp32_payload(fetch_json(config["esp32_data_url"], float(config["timeout_seconds"])))
    post_reading(config["aqualogic_backend_url"], config["device_key"], payload, float(config["timeout_seconds"]))
    LOG.info("Forwarded temperature=%s°C pH=%s turbidity=%sNTU TDS=%sppm", payload["temperature"], payload["ph"], payload["turbidity"], payload["tds"])


def run_once(config: dict) -> None:
    failures: list[BaseException] = []
    try:
        poll_sensor_once(config)
    except (BridgeError, HTTPError, URLError, TimeoutError, OSError) as error:
        failures.append(error)
        LOG.warning("Sensor poll failed (%s)", safe_error(error))

    if config.get("actuator_enabled", True):
        try:
            process_pending_actuator_commands(config)
        except (BridgeError, HTTPError, URLError, TimeoutError, OSError) as error:
            failures.append(error)
            LOG.warning("Actuator backend poll failed (%s)", safe_error(error))
        try:
            refresh_actuator_states(config)
        except (BridgeError, HTTPError, URLError, TimeoutError, OSError) as error:
            failures.append(error)
            LOG.warning("Actuator state poll failed (%s)", safe_error(error))

    if failures:
        raise failures[0]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", default="bridge-config.json", type=Path)
    parser.add_argument("--once", action="store_true", help="Poll and submit exactly one sensor reading and actuator cycle")
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    try:
        config = load_config(args.config)
    except BridgeError as error:
        LOG.error("Configuration error: %s", safe_error(error))
        return 2
    failures = 0
    while True:
        try:
            run_once(config)
            failures = 0
        except (BridgeError, HTTPError, URLError, TimeoutError, OSError) as error:
            failures += 1
            LOG.warning("Bridge cycle failed (%s)", safe_error(error))
        if args.once:
            return 0 if failures == 0 else 1
        delay = min(float(config["poll_interval_seconds"]) * (2 ** min(failures, 4)), 300)
        if failures:
            LOG.info("Retrying bridge polling in %.0f seconds", delay)
        time.sleep(delay)


if __name__ == "__main__":
    raise SystemExit(main())

"""Temporary read-only bridge from an ESP32 /data endpoint to AquaLogic."""
from __future__ import annotations

import argparse
import json
import logging
import math
import time
from datetime import datetime, timezone
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


LOG = logging.getLogger("aqualogic.bridge")
LIMITS = {"temperature": (-10, 60), "ph": (0, 14), "turbidity": (0, 3000), "tds": (0, 5000)}
FIELD_MAP = {"temp_c": "temperature", "ph_value": "ph", "turbidity_ntu": "turbidity", "tds_ppm": "tds"}


class BridgeError(ValueError):
    pass


def translate_esp32_payload(payload: object) -> dict[str, float]:
    if not isinstance(payload, dict):
        raise BridgeError("ESP32 response must be a JSON object")
    translated: dict[str, float] = {}
    for source, target in FIELD_MAP.items():
        value = payload.get(source)
        if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
            raise BridgeError(f"ESP32 field {source!r} must be a finite number")
        minimum, maximum = LIMITS[target]
        if not minimum <= value <= maximum:
            raise BridgeError(f"ESP32 field {source!r} is outside the accepted range")
        translated[target] = float(value)
    translated["observed_at"] = datetime.now(timezone.utc).isoformat()
    return translated


def fetch_json(url: str, timeout: float) -> object:
    request = Request(url, headers={"Accept": "application/json"}, method="GET")
    with urlopen(request, timeout=timeout) as response:  # nosec B310: URL is deliberate local bridge configuration
        if response.status != 200:
            raise BridgeError(f"ESP32 returned HTTP {response.status}")
        try:
            return json.loads(response.read().decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise BridgeError("ESP32 returned invalid JSON") from error


def post_reading(url: str, device_key: str, payload: dict[str, float], timeout: float) -> None:
    body = json.dumps(payload).encode("utf-8")
    request = Request(url.rstrip("/") + "/device-ingestion/readings", data=body, headers={"Content-Type": "application/json", "Accept": "application/json", "X-Device-Key": device_key}, method="POST")
    with urlopen(request, timeout=timeout) as response:  # nosec B310: backend URL is deliberate bridge configuration
        if response.status not in (200, 201):
            raise BridgeError(f"AquaLogic returned HTTP {response.status}")


def load_config(path: Path) -> dict:
    try:
        config = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise BridgeError(f"Could not read configuration: {error}") from error
    required = ("esp32_data_url", "aqualogic_backend_url", "device_key")
    missing = [key for key in required if not isinstance(config.get(key), str) or not config[key].strip()]
    if missing:
        raise BridgeError("Missing configuration values: " + ", ".join(missing))
    config.setdefault("poll_interval_seconds", 15)
    config.setdefault("timeout_seconds", 5)
    if any(isinstance(config[key], bool) or not isinstance(config[key], (int, float)) or config[key] <= 0 for key in ("poll_interval_seconds", "timeout_seconds")):
        raise BridgeError("Polling interval and timeout must be positive")
    return config


def run_once(config: dict) -> None:
    payload = translate_esp32_payload(fetch_json(config["esp32_data_url"], float(config["timeout_seconds"])))
    post_reading(config["aqualogic_backend_url"], config["device_key"], payload, float(config["timeout_seconds"]))
    LOG.info("Forwarded temperature=%s°C pH=%s turbidity=%sNTU TDS=%sppm", payload["temperature"], payload["ph"], payload["turbidity"], payload["tds"])


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", default="bridge-config.json", type=Path)
    parser.add_argument("--once", action="store_true", help="Poll and submit exactly one reading")
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    try:
        config = load_config(args.config)
    except BridgeError as error:
        LOG.error("Configuration error: %s", error)
        return 2
    failures = 0
    while True:
        try:
            run_once(config)
            failures = 0
        except (BridgeError, HTTPError, URLError, TimeoutError, OSError) as error:
            failures += 1
            LOG.warning("Bridge poll failed (%s): %s", type(error).__name__, error)
        if args.once:
            return 0 if failures == 0 else 1
        delay = min(float(config["poll_interval_seconds"]) * (2 ** min(failures, 4)), 300)
        if failures:
            LOG.info("Retrying in %.0f seconds", delay)
        time.sleep(delay)


if __name__ == "__main__":
    raise SystemExit(main())

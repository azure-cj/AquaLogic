import json
import sys
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

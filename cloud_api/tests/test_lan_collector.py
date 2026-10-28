from __future__ import annotations

import json
import os
import secrets
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from cloud_api.lan_collector import (
    CollectorError,
    _confirm_ack,
    _isolate_future_events,
    _load_config,
    _source_events,
    collect,
)


class LanCollectorTest(unittest.TestCase):
    def test_future_record_does_not_block_replay_or_new_measurements(self) -> None:
        # Reproduce production: API accepted valid rows but rejected a 2056 row,
        # so the old collector never advanced its cursor or refreshed the hub.
        from cloud_api.tests.test_api import CloudApiTest
        api = CloudApiTest()
        api.setUp()
        self.addCleanup(api.tearDown)
        now = int(api.now.timestamp())
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            state = root / "state.json"
            hub = root / "hub.json"
            token = root / "device.token"
            token.write_text(api.device_token, encoding="utf-8")
            token.chmod(0o600)
            node = {"name": "greenhouse-01", "sourceUrl": "http://192.168.0.37",
                    "sourceDeviceId": "culture-ldr-01", "cloudDeviceId": api.device_id,
                    "tokenFile": str(token)}
            config = root / "config.json"
            config.write_text(json.dumps({"apiBaseUrl": "http://127.0.0.1:8080",
                                         "stateFile": str(state), "hubStatusFile": str(hub),
                                         "nodes": [node]}), encoding="utf-8")
            good = {"deviceId": node["sourceDeviceId"], "timestamp": now - 60,
                    "temperature": 23.2, "humidity": 70.0, "vpd": 0.85}
            future = {**good, "timestamp": 2_744_700_300}
            readings = [good, future]
            legacy = _source_events(readings, source_id=node["sourceDeviceId"],
                                    cloud_id=api.device_id, first_sequence=1, capabilities={})
            partial = api.ingest(legacy)
            self.assertEqual(partial.body["acceptedThrough"], 1)
            self.assertEqual(partial.body["rejected"][0]["code"], "timestamp_in_future")

            sent = []
            def respond(_opener, request, **_kwargs):
                if request.full_url.endswith("/status"):
                    return {**good, "capabilities": {}}
                if "/readings?" in request.full_url:
                    since = int(request.full_url.split("since=")[1])
                    return [row for row in readings if row["timestamp"] > since]
                payload = json.loads(request.data)
                sent.extend(payload["readings"])
                response = api.service.handle("POST", f"/api/v1/devices/{api.device_id}/telemetry",
                                              headers={"Authorization": request.get_header("Authorization")},
                                              body=request.data, remote_ip="127.0.0.1")
                self.assertEqual(response.status, 200)
                return response.body

            with mock.patch("cloud_api.lan_collector._request_json", side_effect=respond), \
                    mock.patch("cloud_api.lan_collector.time.time", return_value=now):
                result = collect(config)
                self.assertEqual(result["nodes"][0]["quarantined"], 1)
                self.assertEqual(json.loads(hub.read_text())["devices"][api.device_id]["status"], "ok")
                readings.insert(1, {**good, "timestamp": now})
                collect(config)
                current = json.loads(hub.read_text())["devices"][api.device_id]
                self.assertEqual(current["measuredAt"], now)
                collect(config)  # Only the same invalid row remains; no false fresh measurement.
                self.assertEqual(json.loads(hub.read_text())["devices"][api.device_id]["measuredAt"], now)
            progress = json.loads(state.read_text())["nodes"]["greenhouse-01"]
            self.assertEqual(progress, {"lastTimestamp": now, "nextSequence": 3})
            self.assertEqual([event["sequence"] for event in sent], [1, 2])
            self.assertEqual(api.service._database.execute("SELECT COUNT(*) FROM telemetry_events").fetchone()[0], 2)
            quarantine = state.with_name("state.json.quarantine.json")
            records = json.loads(quarantine.read_text())["events"]
            self.assertEqual(len(records), 1)
            record = next(iter(records.values()))
            self.assertEqual(record["event"]["timestamp"], future["timestamp"])
            self.assertNotIn("sequence", record["event"])
            self.assertNotIn(api.device_token, quarantine.read_text())
            if os.name != "nt":
                self.assertEqual(quarantine.stat().st_mode & 0o777, 0o600)

    def test_quarantine_failure_never_silently_discards_records(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "quarantine.json"
            path.write_text("invalid", encoding="utf-8")
            with self.assertRaisesRegex(CollectorError, "Quarantaine"):
                _isolate_future_events([{"timestamp": 1000, "sequence": 1}], path, now=0)
            self.assertEqual(path.read_text(), "invalid")

    def test_ack_allows_already_committed_batch_but_rejects_partial_or_invalid_ack(self) -> None:
        _confirm_ack({"acceptedThrough": 12, "rejected": []}, 10)
        for ack in (None, {}, {"acceptedThrough": True, "rejected": []},
                    {"acceptedThrough": 9, "rejected": []},
                    {"acceptedThrough": 12, "rejected": [{"code": "event_id_conflict"}]}):
            with self.subTest(ack=ack), self.assertRaises(CollectorError):
                _confirm_ack(ack, 10)
        with self.assertRaisesRegex(CollectorError, "timestamp_in_future"):
            _confirm_ack({"acceptedThrough": 10, "rejected": [{"code": "timestamp_in_future"}]}, 11)

    def test_config_restricts_sources_and_api_to_private_boundaries(self) -> None:
        test_root = Path("cloud_api/.test-data").resolve()
        test_root.mkdir(parents=True, exist_ok=True)
        stem = f"config-{secrets.token_hex(8)}"
        config = test_root / f"{stem}.json"
        try:
            base = {
                "apiBaseUrl": "http://127.0.0.1:8080",
                "stateFile": str(test_root / f"{stem}.state.json"),
                "nodes": [
                    {
                        "name": "greenhouse-01",
                        "sourceUrl": "http://192.168.0.37",
                        "sourceDeviceId": "culture-ldr-01",
                        "cloudDeviceId": "dev_example",
                        "tokenFile": str(test_root / f"{stem}.token"),
                    }
                ],
            }
            config.write_text(json.dumps(base), encoding="utf-8")
            self.assertEqual(_load_config(config)["nodes"][0]["sourceUrl"], "http://192.168.0.37")

            for unsafe in (
                "http://example.com",
                "http://127.0.0.1",
                "http://169.254.1.1",
                "http://0.0.0.0",
                "http://user:pass@192.168.0.37",
            ):
                base["nodes"][0]["sourceUrl"] = unsafe
                config.write_text(json.dumps(base), encoding="utf-8")
                with self.assertRaises(CollectorError):
                    _load_config(config)

            base["nodes"][0]["sourceUrl"] = "http://192.168.0.37"
            base["apiBaseUrl"] = "http://192.168.0.21:8080"
            config.write_text(json.dumps(base), encoding="utf-8")
            with self.assertRaises(CollectorError):
                _load_config(config)
        finally:
            config.unlink(missing_ok=True)

    def test_source_readings_become_contiguous_cloud_events(self) -> None:
        events = _source_events(
            [
                {
                    "deviceId": "culture-ldr-01",
                    "timestamp": 1_789_400_000,
                    "temperature": 23.2,
                    "humidity": 70.0,
                    "vpd": 0.85,
                    "lightRaw": 3210,
                    "lightOn": True,
                }
            ],
            source_id="culture-ldr-01",
            cloud_id="dev_example",
            first_sequence=7,
            capabilities={"light_adc_raw": {"type": "number"}},
        )
        self.assertEqual(events[0]["sequence"], 7)
        self.assertEqual(events[0]["deviceId"], "dev_example")
        self.assertEqual(events[0]["measurements"]["light_adc_raw"]["value"], 3210)
        self.assertIs(events[0]["measurements"]["light_detected"], True)

    def test_collect_persists_progress_only_after_api_ack(self) -> None:
        test_root = Path("cloud_api/.test-data").resolve()
        test_root.mkdir(parents=True, exist_ok=True)
        stem = f"collect-{secrets.token_hex(8)}"
        token = test_root / f"{stem}.token"
        config = test_root / f"{stem}.json"
        state = test_root / f"{stem}.state.json"
        hub_status = test_root / f"{stem}.hub.json"
        try:
            token.write_text("gt_dev_" + "x" * 50, encoding="utf-8")
            if os.name != "nt":
                token.chmod(0o600)
            config.write_text(
                json.dumps(
                    {
                        "apiBaseUrl": "http://127.0.0.1:8080",
                        "stateFile": str(state),
                        "hubStatusFile": str(hub_status),
                        "nodes": [
                            {
                                "name": "greenhouse-01",
                                "sourceUrl": "http://192.168.0.37",
                                "sourceDeviceId": "culture-ldr-01",
                                "cloudDeviceId": "dev_example",
                                "tokenFile": str(token),
                            }
                        ],
                    }
                ),
                encoding="utf-8",
            )
            status = {
                "deviceId": "culture-ldr-01",
                "firmwareVersion": "0.3.3",
                "capabilities": {},
            }
            readings = [
                {
                    "deviceId": "culture-ldr-01",
                    "timestamp": 1_789_400_000,
                    "temperature": 23.2,
                    "humidity": 70.0,
                    "vpd": 0.85,
                }
            ]
            ack = {"acceptedThrough": 1, "rejected": []}
            with mock.patch(
                "cloud_api.lan_collector._request_json",
                side_effect=[status, readings, ack],
            ):
                result = collect(config)
            self.assertEqual(result["nodes"][0]["accepted"], 1)
            stored = json.loads(state.read_text(encoding="utf-8"))
            self.assertEqual(stored["nodes"]["greenhouse-01"]["lastTimestamp"], 1_789_400_000)
            self.assertEqual(stored["nodes"]["greenhouse-01"]["nextSequence"], 2)
            public_view = json.loads(hub_status.read_text(encoding="utf-8"))
            device = public_view["devices"]["dev_example"]
            self.assertEqual(device["metrics"]["temperature_c"], 23.2)
            self.assertNotIn("gt_dev_", hub_status.read_text(encoding="utf-8"))
            with mock.patch(
                "cloud_api.lan_collector._request_json",
                side_effect=CollectorError("Connexion impossible"),
            ):
                with self.assertRaises(CollectorError):
                    collect(config)
            offline = json.loads(hub_status.read_text(encoding="utf-8"))["devices"]["dev_example"]
            self.assertEqual(offline["status"], "offline")
            self.assertEqual(offline["measuredAt"], 1_789_400_000)
        finally:
            token.unlink(missing_ok=True)
            config.unlink(missing_ok=True)
            state.unlink(missing_ok=True)
            hub_status.unlink(missing_ok=True)

    def test_three_nodes_keep_distinct_cloud_ids_and_tokens(self) -> None:
        test_root = Path("cloud_api/.test-data").resolve()
        test_root.mkdir(parents=True, exist_ok=True)
        stem = f"multi-{secrets.token_hex(8)}"
        config = test_root / f"{stem}.json"
        state = test_root / f"{stem}.state.json"
        hub_status = test_root / f"{stem}.hub.json"
        tokens = [test_root / f"{stem}-{index}.token" for index in range(3)]
        nodes = [
            {
                "name": f"greenhouse-{index}",
                "sourceUrl": f"http://192.168.0.{37 + index}",
                "sourceDeviceId": f"culture-{index}",
                "cloudDeviceId": f"dev_{index}",
                "tokenFile": str(tokens[index]),
            }
            for index in range(3)
        ]
        sent_tokens = {}
        try:
            for index, path in enumerate(tokens):
                path.write_text("gt_dev_" + str(index) * 50, encoding="utf-8")
                if os.name != "nt":
                    path.chmod(0o600)
            config.write_text(json.dumps({
                "apiBaseUrl": "http://127.0.0.1:8080",
                "stateFile": str(state),
                "hubStatusFile": str(hub_status),
                "nodes": nodes,
            }), encoding="utf-8")

            def response(_opener, request, **_kwargs):
                url = request.full_url
                if url.endswith("/status"):
                    index = int(url.split(".")[-1].split("/")[0]) - 37
                    return {"deviceId": f"culture-{index}", "capabilities": {}}
                if "/readings?" in url:
                    index = int(url.split(".")[-1].split("/")[0]) - 37
                    return [{"deviceId": f"culture-{index}", "timestamp": 1_789_400_000,
                             "temperature": 20 + index, "humidity": 60.0, "vpd": 0.9}]
                payload = json.loads(request.data)
                sent_tokens[payload["deviceId"]] = request.get_header("Authorization")
                return {"acceptedThrough": 1, "rejected": []}

            with mock.patch("cloud_api.lan_collector._request_json", side_effect=response):
                result = collect(config)
            self.assertEqual(len(result["nodes"]), 3)
            self.assertEqual(set(json.loads(hub_status.read_text())["devices"]),
                             {"dev_0", "dev_1", "dev_2"})
            self.assertEqual(set(json.loads(state.read_text())["nodes"]),
                             {"greenhouse-0", "greenhouse-1", "greenhouse-2"})
            self.assertEqual(len(set(sent_tokens.values())), 3)
            self.assertEqual(sent_tokens["dev_2"], "Bearer gt_dev_" + "2" * 50)
        finally:
            for path in [config, state, hub_status, *tokens]:
                path.unlink(missing_ok=True)


if __name__ == "__main__":
    unittest.main()

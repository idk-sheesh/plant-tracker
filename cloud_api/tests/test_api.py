from __future__ import annotations

import base64
import json
import secrets
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path

from cloud_api.app import CloudService


class CloudApiTest(unittest.TestCase):
    def setUp(self) -> None:
        self.now = datetime(2026, 7, 26, 12, 0, 0, tzinfo=timezone.utc)
        self.service = CloudService(clock=lambda: self.now)
        self.password = secrets.token_urlsafe(18) + "Aa1!"
        self.password_other = secrets.token_urlsafe(18) + "Bb2!"
        self.username = "owner_" + secrets.token_hex(4)
        self.other_username = "other_" + secrets.token_hex(4)
        self.register(self.username, self.password)
        self.register(self.other_username, self.password_other)
        login = self.call(
            "POST",
            "/api/v1/auth/login",
            {"username": self.username, "password": self.password},
        )
        self.assertEqual(login.status, 200)
        self.user_token = login.body["sessionToken"]
        other_login = self.call(
            "POST",
            "/api/v1/auth/login",
            {"username": self.other_username, "password": self.password_other},
        )
        self.other_token = other_login.body["sessionToken"]
        provision = self.call(
            "POST",
            "/api/v1/devices",
            {"name": "Serre principale", "firmwareVersion": "0.3.0"},
            token=self.user_token,
        )
        self.assertEqual(provision.status, 200)
        self.device_id = provision.body["device"]["id"]
        self.device_token = provision.body["deviceToken"]

    def tearDown(self) -> None:
        self.service.close()

    def call(
        self,
        method: str,
        path: str,
        payload: dict | None = None,
        *,
        token: str | None = None,
        headers: dict[str, str] | None = None,
    ):
        request_headers = dict(headers or {})
        if token is not None:
            request_headers["Authorization"] = f"Bearer {token}"
        body = b"" if payload is None else json.dumps(payload).encode("utf-8")
        return self.service.handle(
            method,
            path,
            headers=request_headers,
            body=body,
            remote_ip="127.0.0.1",
        )

    def register(self, username: str, password: str) -> None:
        response = self.call(
            "POST",
            "/api/v1/auth/register",
            {"username": username, "password": password},
        )
        self.assertEqual(response.status, 200)

    def event(self, sequence: int, *, event_id: str | None = None, vpd: float | None = None) -> dict:
        event_id = event_id or f"evt-{sequence}"
        value = {
            "deviceId": self.device_id,
            "eventId": event_id,
            "sequence": sequence,
            "measuredAt": self.now.isoformat().replace("+00:00", "Z"),
            "temperatureC": 25.0,
            "humidityPercent": 50.0,
        }
        if vpd is not None:
            value["vpdKpa"] = vpd
        return value

    def ingest(self, events: list[dict]) -> object:
        return self.call(
            "POST",
            f"/api/v1/devices/{self.device_id}/telemetry",
            {
                "schemaVersion": 1,
                "deviceId": self.device_id,
                "firmwareVersion": "0.3.0",
                "readings": events,
            },
            token=self.device_token,
        )

    def test_owner_isolation_and_security_headers(self) -> None:
        response = self.call("GET", "/api/v1/devices", token=self.other_token)
        self.assertEqual(response.status, 200)
        self.assertEqual(response.body["devices"], [])

        hidden = self.call(
            "GET",
            f"/api/v1/devices/{self.device_id}",
            token=self.other_token,
        )
        self.assertEqual(hidden.status, 404)
        self.assertEqual(hidden.body["error"]["code"], "not_found")
        self.assertEqual(hidden.headers["X-Content-Type-Options"], "nosniff")
        self.assertEqual(hidden.headers["X-Robots-Tag"], "noindex, nofollow")
        self.assertIn("X-Request-ID", hidden.headers)

    def test_chart_is_time_bounded_and_owner_scoped(self) -> None:
        self.assertEqual(self.ingest([self.event(1)]).status, 200)
        path = f"/api/v1/devices/{self.device_id}/chart?hours=24"
        chart = self.call("GET", path, token=self.user_token)
        self.assertEqual(chart.status, 200)
        self.assertEqual(len(chart.body["readings"]), 1)
        self.assertEqual(chart.body["readings"][0]["temperatureC"], 25.0)
        self.assertFalse(chart.body["truncated"])
        self.assertEqual(self.call("GET", path, token=self.other_token).status, 404)
        self.assertEqual(self.call("GET", path).status, 401)
        invalid = self.call(
            "GET", f"/api/v1/devices/{self.device_id}/chart?hours=999",
            token=self.user_token,
        )
        self.assertEqual(invalid.status, 400)

    def test_token_is_hashed_and_not_returned_by_device_listing(self) -> None:
        devices = self.call("GET", "/api/v1/devices", token=self.user_token)
        self.assertEqual(devices.status, 200)
        listed = devices.body["devices"][0]
        self.assertNotIn("deviceToken", listed)
        credential = self.service._database.execute(
            "SELECT token_hash FROM device_credentials WHERE device_id = ?",
            (self.device_id,),
        ).fetchone()
        self.assertNotEqual(credential["token_hash"], self.device_token)

    def test_session_logout_revokes_access(self) -> None:
        logout = self.call(
            "POST",
            "/api/v1/auth/logout",
            token=self.user_token,
        )
        self.assertEqual(logout.status, 200)
        after_logout = self.call(
            "GET",
            "/api/v1/devices",
            token=self.user_token,
        )
        self.assertEqual(after_logout.status, 401)

    def test_contiguous_ack_duplicate_and_conflicts(self) -> None:
        first = self.ingest([self.event(1), self.event(3)])
        self.assertEqual(first.status, 200)
        self.assertEqual(first.body["acceptedThrough"], 1)
        self.assertEqual(first.body["acceptedEventIds"], ["evt-1", "evt-3"])

        duplicate = self.ingest([self.event(1)])
        self.assertEqual(duplicate.status, 200)
        self.assertEqual(duplicate.body["acceptedThrough"], 1)
        self.assertEqual(duplicate.body["acceptedEventIds"], ["evt-1"])

        filled = self.ingest([self.event(2)])
        self.assertEqual(filled.status, 200)
        self.assertEqual(filled.body["acceptedThrough"], 3)

        event_conflict = self.ingest([self.event(2, event_id="different-event")])
        self.assertEqual(event_conflict.status, 200)
        self.assertEqual(event_conflict.body["rejected"][0]["code"], "sequence_conflict")

        content_conflict = self.ingest([self.event(1, vpd=1.5)])
        self.assertEqual(content_conflict.status, 200)
        self.assertEqual(content_conflict.body["rejected"][0]["code"], "event_id_conflict")

    def test_server_vpd_is_authoritative_and_invalid_values_are_rejected(self) -> None:
        rejected = self.ingest([self.event(1, vpd=9.9)])
        self.assertEqual(rejected.status, 200)
        self.assertEqual(rejected.body["status"], "rejected")
        self.assertEqual(rejected.body["rejected"][0]["code"], "vpd_mismatch")

        accepted = self.ingest([self.event(1)])
        self.assertEqual(accepted.status, 200)
        latest = self.call(
            "GET",
            f"/api/v1/devices/{self.device_id}/latest",
            token=self.user_token,
        )
        self.assertAlmostEqual(latest.body["vpdKpa"], 1.5839, places=4)
        self.assertEqual(latest.body["serverVpd"], latest.body["vpdKpa"])

        too_old = self.event(2)
        too_old["measuredAt"] = "2020-01-01T00:00:00Z"
        response = self.ingest([too_old])
        self.assertEqual(response.body["rejected"][0]["code"], "timestamp_too_old")

    def test_generic_measurements_are_validated_and_returned(self) -> None:
        event = self.event(1)
        event["capabilities"] = {
            "light_adc_raw": {
                "type": "number",
                "label": "Lumière brute",
                "unit": "ADC",
                "min": 0,
                "max": 4095,
            },
            "light_detected": {"type": "boolean", "label": "Éclairage détecté"},
        }
        event["measurements"] = {
            "light_adc_raw": {"value": 3488, "unit": "ADC", "quality": "uncalibrated"},
            "light_detected": True,
        }
        self.assertEqual(self.ingest([event]).body["status"], "accepted")

        latest = self.call(
            "GET",
            f"/api/v1/devices/{self.device_id}/latest",
            token=self.user_token,
        )
        self.assertEqual(latest.body["measurements"]["light_adc_raw"]["value"], 3488.0)
        self.assertIs(latest.body["measurements"]["light_detected"], True)
        self.assertEqual(latest.body["capabilities"]["light_adc_raw"]["unit"], "ADC")

    def test_generic_measurements_reject_unsafe_or_incoherent_payloads(self) -> None:
        invalid_key = self.event(1)
        invalid_key["measurements"] = {"../secret": 1}
        response = self.ingest([invalid_key])
        self.assertEqual(response.body["rejected"][0]["code"], "invalid_measurement_key")

        mismatch = self.event(2)
        mismatch["capabilities"] = {"light": {"type": "boolean"}}
        mismatch["measurements"] = {"light": 123}
        response = self.ingest([mismatch])
        self.assertEqual(response.body["rejected"][0]["code"], "measurement_type_mismatch")

    def test_cursor_and_token_rotation_revoke(self) -> None:
        self.assertEqual(self.ingest([self.event(1), self.event(2)]).status, 200)
        page = self.call(
            "GET",
            f"/api/v1/devices/{self.device_id}/readings?limit=1",
            token=self.user_token,
        )
        self.assertEqual(page.status, 200)
        self.assertEqual(len(page.body["readings"]), 1)
        next_cursor = page.body["nextCursor"]
        second_page = self.call(
            "GET",
            f"/api/v1/devices/{self.device_id}/readings?cursor={next_cursor}",
            token=self.user_token,
        )
        self.assertEqual([item["sequence"] for item in second_page.body["readings"]], [2])

        rotated = self.call(
            "POST",
            f"/api/v1/devices/{self.device_id}/rotate-token",
            token=self.user_token,
        )
        self.assertEqual(rotated.status, 200)
        new_token = rotated.body["deviceToken"]
        old_response = self.ingest([self.event(3)])
        self.assertEqual(old_response.status, 401)
        new_response = self.call(
            "POST",
            f"/api/v1/devices/{self.device_id}/telemetry",
            {
                "schemaVersion": 1,
                "deviceId": self.device_id,
                "readings": [self.event(3)],
            },
            token=new_token,
        )
        self.assertEqual(new_response.status, 200)

        revoked = self.call(
            "POST",
            f"/api/v1/devices/{self.device_id}/revoke",
            token=self.user_token,
        )
        self.assertEqual(revoked.status, 200)
        self.assertEqual(
            self.call(
                "POST",
                f"/api/v1/devices/{self.device_id}/telemetry",
                {
                    "schemaVersion": 1,
                    "deviceId": self.device_id,
                    "readings": [self.event(4)],
                },
                token=new_token,
            ).status,
            401,
        )

    def test_owner_controlled_backfill_accepts_historical_readings_without_advancing_device_ack(self) -> None:
        historical = self.event(1784937600, event_id="backfill-2026-07-21-1200")
        historical["measuredAt"] = "2026-07-21T12:00:00Z"
        response = self.call(
            "POST",
            f"/api/v1/devices/{self.device_id}/backfill",
            {
                "schemaVersion": 1,
                "deviceId": self.device_id,
                "readings": [historical],
            },
            token=self.user_token,
        )
        self.assertEqual(response.status, 200)
        self.assertEqual(response.body["status"], "accepted")
        self.assertEqual(response.body["acceptedThrough"], 0)
        self.assertEqual(response.body["acceptedEventIds"], [historical["eventId"]])

        readings = self.call(
            "GET",
            f"/api/v1/devices/{self.device_id}/readings",
            token=self.user_token,
        )
        self.assertEqual(readings.status, 200)
        self.assertEqual(readings.body["readings"][0]["source"], "app-backfill")

    def test_backfill_does_not_hide_new_device_readings_or_replace_latest(self) -> None:
        self.assertEqual(self.ingest([self.event(1)]).status, 200)
        first_page = self.call(
            "GET",
            f"/api/v1/devices/{self.device_id}/readings?limit=1",
            token=self.user_token,
        )
        cursor = first_page.body["nextCursor"]

        historical = self.event(1784937600, event_id="backfill-old")
        historical["measuredAt"] = "2026-07-21T12:00:00Z"
        self.assertEqual(
            self.call(
                "POST",
                f"/api/v1/devices/{self.device_id}/backfill",
                {
                    "schemaVersion": 1,
                    "deviceId": self.device_id,
                    "readings": [historical],
                },
                token=self.user_token,
            ).status,
            200,
        )
        self.assertEqual(self.ingest([self.event(2)]).status, 200)

        resumed = self.call(
            "GET",
            f"/api/v1/devices/{self.device_id}/readings?cursor={cursor}&since=9999999999",
            token=self.user_token,
        )
        self.assertEqual(
            [item["eventId"] for item in resumed.body["readings"]],
            ["backfill-old", "evt-2"],
        )
        latest = self.call(
            "GET",
            f"/api/v1/devices/{self.device_id}/latest",
            token=self.user_token,
        )
        self.assertEqual(latest.body["eventId"], "evt-2")

    def test_legacy_sequence_cursor_replays_safely_and_is_upgraded(self) -> None:
        self.assertEqual(self.ingest([self.event(1)]).status, 200)
        legacy_cursor = base64.urlsafe_b64encode(b"seq:9999999999").decode("ascii").rstrip("=")

        page = self.call(
            "GET",
            f"/api/v1/devices/{self.device_id}/readings?cursor={legacy_cursor}",
            token=self.user_token,
        )

        self.assertEqual([item["sequence"] for item in page.body["readings"]], [1])
        self.assertNotEqual(page.body["nextCursor"], legacy_cursor)

    def test_database_backup_is_readable(self) -> None:
        destination = Path("cloud_api") / ".test-cloud-backup.sqlite"
        try:
            self.service.backup(destination)
            self.assertTrue(destination.exists())
            backup = CloudService(destination)
            try:
                self.assertIsNotNone(
                    backup._database.execute(
                        "SELECT id FROM devices WHERE id = ?", (self.device_id,)
                    ).fetchone()
                )
            finally:
                backup.close()
        finally:
            destination.unlink(missing_ok=True)


if __name__ == "__main__":
    unittest.main()

from __future__ import annotations

import json
import shutil
import unittest
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path

from camera_gateway.app import CameraGatewayConfig, CameraGatewayService


class CameraGatewayTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = Path("camera_gateway/.test-data") / uuid.uuid4().hex
        self.temporary.mkdir(parents=True)
        self.addCleanup(shutil.rmtree, self.temporary, True)
        self.now = datetime(2026, 8, 20, 12, 0, 0, tzinfo=timezone.utc)
        self.config = CameraGatewayConfig(
            camera_id="cam-01",
            camera_name="Caméra serre de tomates",
            zone_id="zone-main",
            device_token="device_" + "a" * 40,
            app_token="app_" + "b" * 40,
        )
        self.service = CameraGatewayService(
            self.config,
            self.temporary / "camera.db",
            self.temporary / "photos",
            clock=lambda: self.now,
        )
        self.addCleanup(self.service.close)

    def call(
        self,
        method: str,
        path: str,
        *,
        token: str | None = None,
        body: bytes = b"",
        content_type: str | None = None,
    ):
        headers = {}
        if token:
            headers["Authorization"] = f"Bearer {token}"
        if content_type:
            headers["Content-Type"] = content_type
        return self.service.handle(
            method,
            path,
            headers=headers,
            body=body,
            remote_ip="127.0.0.1",
        )

    @property
    def jpeg(self) -> bytes:
        return b"\xff\xd8\xff" + b"x" * 2048 + b"\xff\xd9"

    def test_requires_the_correct_audience_token(self) -> None:
        missing = self.call("GET", "/api/v1/cameras/cam-01/status")
        self.assertEqual(missing.status, 401)

        device_on_app = self.call(
            "GET",
            "/api/v1/cameras/cam-01/status",
            token=self.config.device_token,
        )
        self.assertEqual(device_on_app.status, 401)

        status = self.call(
            "GET",
            "/api/v1/cameras/cam-01/status",
            token=self.config.app_token,
        )
        self.assertEqual(status.status, 200)
        self.assertEqual(status.body["camera"]["zoneId"], "zone-main")

    def test_capture_round_trip_and_idempotent_upload(self) -> None:
        requested = self.call(
            "POST",
            "/api/v1/cameras/cam-01/captures",
            token=self.config.app_token,
        )
        self.assertEqual(requested.status, 202)
        command_id = requested.body["command"]["id"]

        polled = self.call(
            "GET",
            "/internal/v1/cameras/cam-01/commands?after=0",
            token=self.config.device_token,
        )
        self.assertEqual(polled.body["command"]["id"], command_id)

        uploaded = self.call(
            "POST",
            f"/internal/v1/cameras/cam-01/snapshots?commandId={command_id}",
            token=self.config.device_token,
            body=self.jpeg,
            content_type="image/jpeg",
        )
        self.assertEqual(uploaded.status, 200)
        self.assertEqual(uploaded.body["status"], "accepted")

        repeated = self.call(
            "POST",
            f"/internal/v1/cameras/cam-01/snapshots?commandId={command_id}",
            token=self.config.device_token,
            body=self.jpeg,
            content_type="image/jpeg",
        )
        self.assertEqual(repeated.body["status"], "already_accepted")

        latest = self.call(
            "GET",
            "/api/v1/cameras/cam-01/snapshots/latest",
            token=self.config.app_token,
        )
        self.assertEqual(latest.status, 200)
        self.assertEqual(latest.body, self.jpeg)
        self.assertIn("ETag", latest.headers)

    def test_cooldown_and_expiration_are_enforced(self) -> None:
        first = self.service.enqueue_capture("telegram")
        limited = self.call(
            "POST",
            "/api/v1/cameras/cam-01/captures",
            token=self.config.app_token,
        )
        self.assertEqual(limited.status, 429)
        self.assertEqual(limited.headers["Retry-After"], "10")

        self.now += timedelta(seconds=36)
        expired = self.call(
            "GET",
            "/internal/v1/cameras/cam-01/commands?after=0",
            token=self.config.device_token,
        )
        self.assertIsNone(expired.body["command"])

        rejected = self.call(
            "POST",
            f"/internal/v1/cameras/cam-01/snapshots?commandId={first['id']}",
            token=self.config.device_token,
            body=self.jpeg,
            content_type="image/jpeg",
        )
        self.assertEqual(rejected.status, 409)
        self.assertEqual(rejected.body["error"]["code"], "command_expired")

    def test_heartbeat_changes_online_status_without_exposing_secrets(self) -> None:
        heartbeat = self.call(
            "POST",
            "/internal/v1/cameras/cam-01/heartbeat",
            token=self.config.device_token,
            body=json.dumps(
                {
                    "firmwareVersion": "0.1.0",
                    "rssiDbm": -61,
                    "freeHeapBytes": 123456,
                    "uptimeSeconds": 42,
                }
            ).encode("utf-8"),
            content_type="application/json",
        )
        self.assertEqual(heartbeat.status, 200)

        status = self.call(
            "GET",
            "/api/v1/cameras/cam-01/status",
            token=self.config.app_token,
        )
        camera = status.body["camera"]
        self.assertEqual(camera["status"], "online")
        self.assertEqual(camera["rssiDbm"], -61)
        self.assertNotIn("token", json.dumps(camera).lower())

    def test_invalid_jpeg_is_rejected_before_storage(self) -> None:
        command = self.service.enqueue_capture("app")
        response = self.call(
            "POST",
            f"/internal/v1/cameras/cam-01/snapshots?commandId={command['id']}",
            token=self.config.device_token,
            body=b"not-a-jpeg" * 200,
            content_type="image/jpeg",
        )
        self.assertEqual(response.status, 422)
        self.assertEqual(list((self.temporary / "photos").rglob("*.jpg")), [])


if __name__ == "__main__":
    unittest.main()

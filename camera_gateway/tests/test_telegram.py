from __future__ import annotations

import shutil
import time
import unittest
import uuid
from pathlib import Path

from camera_gateway.app import CameraGatewayConfig, CameraGatewayService
from camera_gateway.telegram import TelegramBotRunner


class FakeTelegramClient:
    def __init__(self) -> None:
        self.messages: list[tuple[str, str]] = []

    def send_message(self, chat_id: str, text: str) -> None:
        self.messages.append((chat_id, text))


class TelegramBotRunnerTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = Path("camera_gateway/.test-data") / uuid.uuid4().hex
        self.temporary.mkdir(parents=True)
        self.addCleanup(shutil.rmtree, self.temporary, True)
        self.service = CameraGatewayService(
            CameraGatewayConfig(
                camera_id="cam-01",
                camera_name="Caméra",
                zone_id="zone-main",
                device_token="device_" + "a" * 40,
                app_token="app_" + "b" * 40,
            ),
            self.temporary / "camera.db",
            self.temporary / "photos",
        )
        self.addCleanup(self.service.close)
        self.client = FakeTelegramClient()
        self.runner = TelegramBotRunner(
            self.service,
            self.client,  # type: ignore[arg-type]
            "12345",
        )

    def update(self, *, chat_id: str, date: int, text: str) -> dict:
        return {
            "update_id": 1,
            "message": {
                "date": date,
                "chat": {"id": chat_id},
                "text": text,
            },
        }

    def test_only_recent_photo_commands_from_the_allowed_chat_are_queued(self) -> None:
        started = int(time.time())
        self.runner._handle_update(
            self.update(chat_id="999", date=started, text="/photo"),
            started,
        )
        self.runner._handle_update(
            self.update(chat_id="12345", date=started - 60, text="/photo"),
            started,
        )
        self.runner._handle_update(
            self.update(chat_id="12345", date=started, text="/photo"),
            started,
        )

        command = self.service.handle(
            "GET",
            "/internal/v1/cameras/cam-01/commands?after=0",
            headers={
                "Authorization": f"Bearer {self.service.config.device_token}",
            },
        )
        self.assertEqual(command.status, 200)
        self.assertIsNotNone(command.body["command"])
        self.assertEqual(self.client.messages, [("12345", "Capture demandée à la caméra.")])


if __name__ == "__main__":
    unittest.main()

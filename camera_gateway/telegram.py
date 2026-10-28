from __future__ import annotations

import json
import queue
import ssl
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from pathlib import Path
from typing import Any

from .app import CameraGatewayService, GatewayError


class TelegramClient:
    def __init__(self, bot_token: str) -> None:
        if len(bot_token) < 32:
            raise ValueError("Token Telegram invalide")
        self._base_url = f"https://api.telegram.org/bot{bot_token}"
        self._ssl_context = ssl.create_default_context()

    def get_updates(self, offset: int, timeout_seconds: int = 20) -> list[dict[str, Any]]:
        query = urllib.parse.urlencode(
            {"offset": offset, "limit": 10, "timeout": timeout_seconds}
        )
        result = self._json_request(
            f"{self._base_url}/getUpdates?{query}",
            method="GET",
            timeout=timeout_seconds + 10,
        )
        updates = result.get("result")
        if updates is None:
            return []
        if not isinstance(updates, list) or any(not isinstance(item, dict) for item in updates):
            raise RuntimeError("Réponse Telegram invalide")
        return updates

    def send_message(self, chat_id: str, text: str) -> None:
        body = urllib.parse.urlencode(
            {"chat_id": chat_id, "text": text, "protect_content": "true"}
        ).encode("utf-8")
        self._json_request(
            f"{self._base_url}/sendMessage",
            method="POST",
            body=body,
            content_type="application/x-www-form-urlencoded",
            timeout=15,
        )

    def send_photo(self, chat_id: str, source: str | Path, caption: str) -> None:
        photo = Path(source).read_bytes()
        boundary = f"----GardenJournal{uuid.uuid4().hex}"
        chunks = [
            self._field(boundary, "chat_id", chat_id),
            self._field(boundary, "caption", caption),
            self._field(boundary, "protect_content", "true"),
            f"--{boundary}\r\n".encode("ascii"),
            b'Content-Disposition: form-data; name="photo"; filename="capture.jpg"\r\n',
            b"Content-Type: image/jpeg\r\n\r\n",
            photo,
            b"\r\n",
            f"--{boundary}--\r\n".encode("ascii"),
        ]
        self._json_request(
            f"{self._base_url}/sendPhoto",
            method="POST",
            body=b"".join(chunks),
            content_type=f"multipart/form-data; boundary={boundary}",
            timeout=30,
        )

    @staticmethod
    def _field(boundary: str, name: str, value: str) -> bytes:
        return (
            f"--{boundary}\r\n"
            f'Content-Disposition: form-data; name="{name}"\r\n\r\n'
            f"{value}\r\n"
        ).encode("utf-8")

    def _json_request(
        self,
        url: str,
        *,
        method: str,
        body: bytes | None = None,
        content_type: str | None = None,
        timeout: int,
    ) -> dict[str, Any]:
        headers = {"Accept": "application/json"}
        if content_type:
            headers["Content-Type"] = content_type
        request = urllib.request.Request(url, data=body, headers=headers, method=method)
        try:
            with urllib.request.urlopen(
                request,
                timeout=timeout,
                context=self._ssl_context,
            ) as response:
                data = response.read(256 * 1024)
        except (urllib.error.URLError, TimeoutError) as error:
            raise RuntimeError("Telegram temporairement indisponible") from error
        try:
            decoded = json.loads(data.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise RuntimeError("Réponse Telegram invalide") from error
        if not isinstance(decoded, dict) or decoded.get("ok") is not True:
            raise RuntimeError("Telegram a refusé la requête")
        return decoded


class TelegramBotRunner:
    def __init__(
        self,
        service: CameraGatewayService,
        client: TelegramClient,
        allowed_chat_id: str,
    ) -> None:
        if not allowed_chat_id.strip():
            raise ValueError("Chat Telegram invalide")
        self._service = service
        self._client = client
        self._allowed_chat_id = allowed_chat_id.strip()
        self._stop = threading.Event()
        self._notifications: queue.Queue[dict[str, Any]] = queue.Queue(maxsize=20)
        self._threads: list[threading.Thread] = []

    def start(self) -> None:
        self._service.set_snapshot_listener(self.notify_snapshot)
        self._threads = [
            threading.Thread(target=self._poll_loop, name="telegram-poll", daemon=True),
            threading.Thread(
                target=self._notification_loop,
                name="telegram-photo",
                daemon=True,
            ),
            threading.Thread(
                target=self._health_loop,
                name="telegram-camera-health",
                daemon=True,
            ),
        ]
        for thread in self._threads:
            thread.start()

    def stop(self) -> None:
        self._service.set_snapshot_listener(None)
        self._stop.set()
        for thread in self._threads:
            thread.join(timeout=35)

    def notify_snapshot(self, event: dict[str, Any]) -> None:
        if event.get("source") != "telegram":
            return
        try:
            self._notifications.put_nowait(event)
        except queue.Full:
            # La photo reste stockée localement. Une saturation Telegram ne doit
            # jamais bloquer l'upload de l'ESP32-CAM.
            return

    def _poll_loop(self) -> None:
        offset = self._service.get_telegram_offset()
        started_at = int(time.time())
        failures = 0
        while not self._stop.is_set():
            try:
                updates = self._client.get_updates(offset)
                failures = 0
                for update in updates:
                    update_id = update.get("update_id")
                    if not isinstance(update_id, int) or update_id < 0:
                        continue
                    offset = max(offset, update_id + 1)
                    self._service.set_telegram_offset(offset)
                    self._handle_update(update, started_at)
            except RuntimeError:
                failures = min(failures + 1, 6)
                self._stop.wait(min(2**failures, 30))

    def _handle_update(self, update: dict[str, Any], started_at: int) -> None:
        message = update.get("message")
        if not isinstance(message, dict):
            return
        chat = message.get("chat")
        text = message.get("text")
        sent_at = message.get("date")
        if not isinstance(chat, dict) or not isinstance(text, str):
            return
        chat_id = str(chat.get("id", ""))
        if chat_id != self._allowed_chat_id:
            return
        if not isinstance(sent_at, int) or sent_at < started_at - 5:
            return
        command = text.strip().split(maxsplit=1)[0]
        if command != "/photo" and not command.startswith("/photo@"):
            return
        try:
            self._service.enqueue_capture("telegram")
            self._safe_message("Capture demandée à la caméra.")
        except GatewayError as error:
            if error.code == "capture_cooldown":
                self._safe_message(
                    f"Patiente encore {error.retry_after or 1} seconde(s) avant une nouvelle photo."
                )
            else:
                self._safe_message("La capture n'a pas pu être demandée.")

    def _notification_loop(self) -> None:
        while not self._stop.is_set():
            try:
                event = self._notifications.get(timeout=1)
            except queue.Empty:
                continue
            try:
                self._client.send_photo(
                    self._allowed_chat_id,
                    str(event["path"]),
                    f"Photo demandée à {event['cameraName']}",
                )
            except (RuntimeError, OSError, KeyError):
                self._safe_message(
                    "La photo a été stockée sur le Raspberry Pi, mais Telegram est indisponible."
                )

    def _health_loop(self) -> None:
        offline_alerted = False
        while not self._stop.wait(30):
            try:
                status = self._service.camera_status()
            except Exception:
                continue
            has_been_seen = status.get("lastSeenAt") is not None
            is_online = status.get("status") == "online"
            if has_been_seen and not is_online and not offline_alerted:
                self._safe_message(
                    f"Alerte : {status.get('name', 'la caméra')} ne répond plus."
                )
                offline_alerted = True
            elif is_online and offline_alerted:
                self._safe_message(
                    f"{status.get('name', 'La caméra')} répond de nouveau."
                )
                offline_alerted = False

    def _safe_message(self, text: str) -> None:
        try:
            self._client.send_message(self._allowed_chat_id, text)
        except RuntimeError:
            return

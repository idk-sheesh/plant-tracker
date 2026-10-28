from __future__ import annotations

import hashlib
import hmac
import json
import os
import re
import sqlite3
import tempfile
import threading
import time
import uuid
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable
from urllib.parse import parse_qs, urlsplit


UTC = timezone.utc
API_PREFIX = "/api/v1"
INTERNAL_PREFIX = "/internal/v1"
IDENTIFIER_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.:-]{0,79}$")
REQUEST_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$")
MAX_JSON_BYTES = 16 * 1024
DEFAULT_MAX_PHOTO_BYTES = 4 * 1024 * 1024


class GatewayError(Exception):
    def __init__(
        self,
        status: int,
        code: str,
        message: str,
        *,
        retry_after: int | None = None,
    ) -> None:
        super().__init__(message)
        self.status = status
        self.code = code
        self.message = message
        self.retry_after = retry_after


@dataclass(frozen=True)
class GatewayResponse:
    status: int
    body: dict[str, Any] | bytes
    headers: dict[str, str]


@dataclass(frozen=True)
class CameraGatewayConfig:
    camera_id: str
    camera_name: str
    zone_id: str
    device_token: str
    app_token: str
    command_cooldown_seconds: int = 10
    command_ttl_seconds: int = 35
    offline_after_seconds: int = 120
    max_photo_bytes: int = DEFAULT_MAX_PHOTO_BYTES

    def __post_init__(self) -> None:
        for label, value in (
            ("camera_id", self.camera_id),
            ("zone_id", self.zone_id),
        ):
            if not IDENTIFIER_RE.fullmatch(value):
                raise ValueError(f"{label} invalide")
        if not self.camera_name.strip() or len(self.camera_name.strip()) > 120:
            raise ValueError("camera_name invalide")
        if len(self.device_token) < 32 or len(self.app_token) < 32:
            raise ValueError("Les jetons caméra et application doivent faire au moins 32 caractères")
        if not 1 <= self.command_cooldown_seconds <= 3600:
            raise ValueError("command_cooldown_seconds invalide")
        if not 5 <= self.command_ttl_seconds <= 300:
            raise ValueError("command_ttl_seconds invalide")
        if not 10 <= self.offline_after_seconds <= 86400:
            raise ValueError("offline_after_seconds invalide")
        if not 64 * 1024 <= self.max_photo_bytes <= 16 * 1024 * 1024:
            raise ValueError("max_photo_bytes invalide")


class SlidingWindowLimiter:
    def __init__(self, limit: int = 300, window_seconds: int = 60) -> None:
        self.limit = limit
        self.window_seconds = window_seconds
        self._events: dict[str, list[float]] = {}
        self._lock = threading.Lock()

    def allow(self, key: str, now: float | None = None) -> bool:
        current = now if now is not None else time.monotonic()
        cutoff = current - self.window_seconds
        with self._lock:
            events = [event for event in self._events.get(key, []) if event > cutoff]
            if len(events) >= self.limit:
                self._events[key] = events
                return False
            events.append(current)
            self._events[key] = events
            return True


class CameraGatewayService:
    """Cœur HTTP indépendant de la passerelle caméra.

    La couche réseau vit dans ``server.py`` afin que l'authentification, les
    migrations, l'idempotence et la validation JPEG soient testables sans
    ouvrir de socket.
    """

    def __init__(
        self,
        config: CameraGatewayConfig,
        database_path: str | Path = ":memory:",
        photo_root: str | Path | None = None,
        *,
        clock: Callable[[], datetime] | None = None,
    ) -> None:
        self.config = config
        self.database_path = str(database_path)
        self.photo_root = Path(photo_root or "camera_gateway/data/photos")
        self.photo_root.mkdir(parents=True, exist_ok=True)
        self.max_body_bytes = config.max_photo_bytes
        self._clock = clock or (lambda: datetime.now(UTC))
        self._write_lock = threading.RLock()
        self._limiter = SlidingWindowLimiter()
        self._snapshot_listener: Callable[[dict[str, Any]], None] | None = None
        self._database = sqlite3.connect(
            self.database_path,
            check_same_thread=False,
            isolation_level=None,
        )
        self._database.row_factory = sqlite3.Row
        self._database.execute("PRAGMA foreign_keys = ON")
        self._database.execute("PRAGMA busy_timeout = 5000")
        if self.database_path != ":memory:":
            self._database.execute("PRAGMA journal_mode = WAL")
        self._migrate()
        self._register_camera()

    def close(self) -> None:
        self._database.close()

    def set_snapshot_listener(
        self,
        listener: Callable[[dict[str, Any]], None] | None,
    ) -> None:
        self._snapshot_listener = listener

    def backup(self, destination: str | Path) -> None:
        destination_path = Path(destination)
        destination_path.parent.mkdir(parents=True, exist_ok=True)
        target = sqlite3.connect(str(destination_path))
        try:
            with target:
                self._database.backup(target)
        finally:
            target.close()

    def handle(
        self,
        method: str,
        path: str,
        *,
        headers: dict[str, str] | None = None,
        body: bytes = b"",
        remote_ip: str = "unknown",
    ) -> GatewayResponse:
        request_headers = {key.lower(): value for key, value in (headers or {}).items()}
        request_id = self._request_id(request_headers.get("x-request-id"))
        if len(body) > self.max_body_bytes:
            return self._error_response(
                GatewayError(413, "payload_too_large", "Requête trop volumineuse"),
                request_id,
            )
        if not self._limiter.allow(f"ip:{remote_ip}"):
            return self._error_response(
                GatewayError(429, "rate_limited", "Trop de requêtes"),
                request_id,
            )

        parsed = urlsplit(path)
        route = parsed.path
        query = parse_qs(parsed.query, keep_blank_values=True)
        try:
            if method.upper() == "OPTIONS":
                raise GatewayError(405, "method_not_allowed", "Méthode non autorisée")
            if route == f"{API_PREFIX}/health" and method.upper() == "GET":
                return self._json_response(
                    200,
                    {"status": "ok", "requestId": request_id},
                    request_id,
                )
            if route == "/robots.txt" and method.upper() == "GET":
                return self._bytes_response(
                    200,
                    b"User-agent: *\nDisallow: /\n",
                    request_id,
                    content_type="text/plain; charset=utf-8",
                )

            camera_id, action, audience = self._match_route(route)
            self._require_camera(camera_id)
            if audience == "device":
                self._authenticate(request_headers, self.config.device_token)
            else:
                self._authenticate(request_headers, self.config.app_token)

            if audience == "device" and action == "commands" and method.upper() == "GET":
                after = self._single_nonnegative_int(query, "after", default=0)
                command = self._next_command(after)
                return self._json_response(
                    200,
                    {"command": command, "requestId": request_id},
                    request_id,
                )
            if audience == "device" and action == "heartbeat" and method.upper() == "POST":
                payload = self._json_body(body)
                result = self._record_heartbeat(payload)
                return self._json_response(200, result, request_id)
            if audience == "device" and action == "snapshots" and method.upper() == "POST":
                command_id = self._single_nonnegative_int(query, "commandId")
                result = self._save_snapshot(
                    command_id,
                    body,
                    request_headers.get("content-type", ""),
                )
                return self._json_response(200, result, request_id)
            if audience == "app" and action == "status" and method.upper() == "GET":
                return self._json_response(200, {"camera": self._status()}, request_id)
            if audience == "app" and action == "captures" and method.upper() == "POST":
                command = self.enqueue_capture("app")
                return self._json_response(
                    202,
                    {"command": command, "requestId": request_id},
                    request_id,
                )
            if audience == "app" and action == "latest" and method.upper() == "GET":
                image, snapshot = self._latest_image()
                return self._bytes_response(
                    200,
                    image,
                    request_id,
                    content_type="image/jpeg",
                    extra_headers={
                        "ETag": f'"{snapshot["sha256"]}"',
                        "X-Snapshot-ID": snapshot["id"],
                        "X-Captured-At": snapshot["capturedAt"],
                    },
                )
            raise GatewayError(405, "method_not_allowed", "Méthode non autorisée")
        except GatewayError as error:
            return self._error_response(error, request_id)
        except sqlite3.IntegrityError:
            return self._error_response(
                GatewayError(409, "conflict", "Opération en conflit"),
                request_id,
            )
        except sqlite3.Error:
            return self._error_response(
                GatewayError(
                    503,
                    "temporary_database_error",
                    "Service temporairement indisponible",
                ),
                request_id,
            )
        except Exception:
            return self._error_response(
                GatewayError(500, "internal_error", "Erreur interne"),
                request_id,
            )

    def enqueue_capture(self, source: str) -> dict[str, Any]:
        if source not in {"app", "telegram"}:
            raise ValueError("Source de commande invalide")
        now = self._now_epoch()
        with self._write_lock:
            self._expire_commands(now)
            previous = self._database.execute(
                """SELECT requested_at FROM capture_commands
                   WHERE camera_id = ? ORDER BY id DESC LIMIT 1""",
                (self.config.camera_id,),
            ).fetchone()
            if previous is not None:
                remaining = (
                    int(previous["requested_at"])
                    + self.config.command_cooldown_seconds
                    - now
                )
                if remaining > 0:
                    raise GatewayError(
                        429,
                        "capture_cooldown",
                        "Une capture vient déjà d'être demandée",
                        retry_after=remaining,
                    )
            expires_at = now + self.config.command_ttl_seconds
            cursor = self._database.execute(
                """INSERT INTO capture_commands(
                       camera_id, source, requested_at, expires_at, status)
                   VALUES (?, ?, ?, ?, 'queued')""",
                (self.config.camera_id, source, now, expires_at),
            )
            command_id = int(cursor.lastrowid)
        return self._command_payload(command_id, now, expires_at, "queued")

    def get_telegram_offset(self) -> int:
        with self._write_lock:
            row = self._database.execute(
                "SELECT value FROM gateway_meta WHERE key = 'telegram_update_offset'"
            ).fetchone()
        return int(row["value"]) if row is not None else 0

    def set_telegram_offset(self, offset: int) -> None:
        if offset < 0:
            raise ValueError("Offset Telegram invalide")
        with self._write_lock:
            self._database.execute(
                """INSERT INTO gateway_meta(key, value) VALUES ('telegram_update_offset', ?)
                   ON CONFLICT(key) DO UPDATE SET value = excluded.value""",
                (str(offset),),
            )

    def camera_status(self) -> dict[str, Any]:
        """Return the non-secret status used by the app and local monitors."""
        return self._status()

    def _match_route(self, route: str) -> tuple[str, str, str]:
        patterns = (
            (
                re.compile(rf"^{INTERNAL_PREFIX}/cameras/([^/]+)/commands$"),
                "commands",
                "device",
            ),
            (
                re.compile(rf"^{INTERNAL_PREFIX}/cameras/([^/]+)/heartbeat$"),
                "heartbeat",
                "device",
            ),
            (
                re.compile(rf"^{INTERNAL_PREFIX}/cameras/([^/]+)/snapshots$"),
                "snapshots",
                "device",
            ),
            (
                re.compile(rf"^{API_PREFIX}/cameras/([^/]+)/status$"),
                "status",
                "app",
            ),
            (
                re.compile(rf"^{API_PREFIX}/cameras/([^/]+)/captures$"),
                "captures",
                "app",
            ),
            (
                re.compile(rf"^{API_PREFIX}/cameras/([^/]+)/snapshots/latest$"),
                "latest",
                "app",
            ),
        )
        for pattern, action, audience in patterns:
            match = pattern.fullmatch(route)
            if match:
                return match.group(1), action, audience
        raise GatewayError(404, "not_found", "Ressource introuvable")

    def _require_camera(self, camera_id: str) -> None:
        if not IDENTIFIER_RE.fullmatch(camera_id) or not hmac.compare_digest(
            camera_id, self.config.camera_id
        ):
            raise GatewayError(404, "not_found", "Ressource introuvable")

    def _authenticate(self, headers: dict[str, str], expected_token: str) -> None:
        authorization = headers.get("authorization", "")
        prefix = "Bearer "
        if not authorization.startswith(prefix):
            raise GatewayError(401, "unauthorized", "Authentification requise")
        supplied = authorization[len(prefix) :]
        if not hmac.compare_digest(supplied, expected_token):
            raise GatewayError(401, "unauthorized", "Authentification requise")

    def _next_command(self, after: int) -> dict[str, Any] | None:
        now = self._now_epoch()
        with self._write_lock:
            self._expire_commands(now)
            row = self._database.execute(
                """SELECT id, requested_at, expires_at, status
                   FROM capture_commands
                   WHERE camera_id = ? AND id > ?
                     AND status IN ('queued', 'delivered')
                     AND expires_at > ?
                   ORDER BY id ASC LIMIT 1""",
                (self.config.camera_id, after, now),
            ).fetchone()
            if row is None:
                return None
            self._database.execute(
                """UPDATE capture_commands
                   SET status = 'delivered', delivered_at = COALESCE(delivered_at, ?)
                   WHERE id = ?""",
                (now, row["id"]),
            )
        return self._command_payload(
            int(row["id"]),
            int(row["requested_at"]),
            int(row["expires_at"]),
            "delivered",
        )

    def _record_heartbeat(self, payload: dict[str, Any]) -> dict[str, Any]:
        firmware_version = self._optional_text(payload.get("firmwareVersion"), 80)
        last_error = self._optional_text(payload.get("lastError"), 240)
        rssi = self._optional_int(payload.get("rssiDbm"), -200, 20)
        free_heap = self._optional_int(payload.get("freeHeapBytes"), 0, 2**31 - 1)
        uptime = self._optional_int(payload.get("uptimeSeconds"), 0, 2**31 - 1)
        now = self._now_epoch()
        with self._write_lock:
            self._database.execute(
                """UPDATE cameras
                   SET last_seen_at = ?, firmware_version = ?, rssi_dbm = ?,
                       free_heap_bytes = ?, uptime_seconds = ?, last_error = ?
                   WHERE id = ?""",
                (
                    now,
                    firmware_version,
                    rssi,
                    free_heap,
                    uptime,
                    last_error,
                    self.config.camera_id,
                ),
            )
        return {"status": "accepted", "serverTime": self._iso(now)}

    def _save_snapshot(
        self,
        command_id: int,
        body: bytes,
        content_type: str,
    ) -> dict[str, Any]:
        if content_type.split(";", 1)[0].strip().lower() != "image/jpeg":
            raise GatewayError(415, "unsupported_media_type", "Un JPEG est requis")
        if len(body) < 1024 or len(body) > self.config.max_photo_bytes:
            raise GatewayError(422, "invalid_photo", "Taille JPEG invalide")
        if not body.startswith(b"\xff\xd8\xff") or not body.endswith(b"\xff\xd9"):
            raise GatewayError(422, "invalid_photo", "Signature JPEG invalide")

        now = self._now_epoch()
        with self._write_lock:
            existing = self._database.execute(
                """SELECT id, captured_at, sha256, size_bytes, stored_path
                   FROM camera_snapshots WHERE command_id = ?""",
                (command_id,),
            ).fetchone()
            if existing is not None:
                snapshot = self._snapshot_payload(existing)
                return {"status": "already_accepted", "snapshot": snapshot}

            command = self._database.execute(
                """SELECT id, source, expires_at, status FROM capture_commands
                   WHERE id = ? AND camera_id = ?""",
                (command_id, self.config.camera_id),
            ).fetchone()
            if command is None:
                raise GatewayError(404, "command_not_found", "Commande inconnue")
            if command["status"] in {"failed", "expired"} or int(command["expires_at"]) <= now:
                self._database.execute(
                    "UPDATE capture_commands SET status = 'expired' WHERE id = ?",
                    (command_id,),
                )
                raise GatewayError(409, "command_expired", "Commande expirée")

            sha256 = hashlib.sha256(body).hexdigest()
            snapshot_id = f"snap_{uuid.uuid4().hex}"
            captured = datetime.fromtimestamp(now, UTC)
            relative = Path(
                f"{captured.year:04d}",
                f"{captured.month:02d}",
                f"{captured.day:02d}",
                f"{captured.strftime('%H%M%S')}_{snapshot_id}.jpg",
            )
            destination = self.photo_root / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            temporary_path: Path | None = None
            try:
                with tempfile.NamedTemporaryFile(
                    dir=destination.parent,
                    prefix=".upload-",
                    suffix=".tmp",
                    delete=False,
                ) as temporary:
                    temporary.write(body)
                    temporary.flush()
                    os.fsync(temporary.fileno())
                    temporary_path = Path(temporary.name)
                os.replace(temporary_path, destination)
                temporary_path = None
                self._database.execute("BEGIN IMMEDIATE")
                try:
                    self._database.execute(
                        """INSERT INTO camera_snapshots(
                               id, camera_id, command_id, captured_at, stored_path,
                               sha256, size_bytes, created_at)
                           VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
                        (
                            snapshot_id,
                            self.config.camera_id,
                            command_id,
                            now,
                            relative.as_posix(),
                            sha256,
                            len(body),
                            now,
                        ),
                    )
                    self._database.execute(
                        """UPDATE capture_commands
                           SET status = 'completed', completed_at = ?, snapshot_id = ?
                           WHERE id = ?""",
                        (now, snapshot_id, command_id),
                    )
                    self._database.execute(
                        "UPDATE cameras SET last_seen_at = ?, last_error = NULL WHERE id = ?",
                        (now, self.config.camera_id),
                    )
                    self._database.execute("COMMIT")
                except Exception:
                    self._database.execute("ROLLBACK")
                    raise
            except Exception:
                if temporary_path is not None:
                    temporary_path.unlink(missing_ok=True)
                destination.unlink(missing_ok=True)
                raise

            row = self._database.execute(
                """SELECT id, captured_at, sha256, size_bytes, stored_path
                   FROM camera_snapshots WHERE id = ?""",
                (snapshot_id,),
            ).fetchone()
            assert row is not None
            snapshot = self._snapshot_payload(row)
            source = str(command["source"])

        listener = self._snapshot_listener
        if listener is not None:
            listener(
                {
                    "cameraId": self.config.camera_id,
                    "cameraName": self.config.camera_name,
                    "source": source,
                    "snapshot": snapshot,
                    "path": str(destination),
                }
            )
        return {"status": "accepted", "snapshot": snapshot}

    def _status(self) -> dict[str, Any]:
        with self._write_lock:
            row = self._database.execute(
                """SELECT id, name, zone_id, last_seen_at, firmware_version,
                          rssi_dbm, free_heap_bytes, uptime_seconds, last_error
                   FROM cameras WHERE id = ?""",
                (self.config.camera_id,),
            ).fetchone()
            assert row is not None
            latest_row = self._database.execute(
                """SELECT id, captured_at, sha256, size_bytes, stored_path
                   FROM camera_snapshots WHERE camera_id = ?
                   ORDER BY captured_at DESC, id DESC LIMIT 1""",
                (self.config.camera_id,),
            ).fetchone()
        now = self._now_epoch()
        last_seen = int(row["last_seen_at"]) if row["last_seen_at"] is not None else None
        online = last_seen is not None and now - last_seen <= self.config.offline_after_seconds
        return {
            "id": row["id"],
            "name": row["name"],
            "zoneId": row["zone_id"],
            "status": "online" if online else "offline",
            "lastSeenAt": self._iso(last_seen) if last_seen is not None else None,
            "firmwareVersion": row["firmware_version"],
            "rssiDbm": row["rssi_dbm"],
            "freeHeapBytes": row["free_heap_bytes"],
            "uptimeSeconds": row["uptime_seconds"],
            "lastError": row["last_error"],
            "latestSnapshot": self._snapshot_payload(latest_row) if latest_row else None,
        }

    def _latest_image(self) -> tuple[bytes, dict[str, Any]]:
        with self._write_lock:
            row = self._database.execute(
                """SELECT id, captured_at, sha256, size_bytes, stored_path
                   FROM camera_snapshots WHERE camera_id = ?
                   ORDER BY captured_at DESC, id DESC LIMIT 1""",
                (self.config.camera_id,),
            ).fetchone()
        if row is None:
            raise GatewayError(404, "snapshot_not_found", "Aucune photo disponible")
        relative = Path(str(row["stored_path"]))
        root = self.photo_root.resolve()
        source = (root / relative).resolve()
        try:
            source.relative_to(root)
        except ValueError as error:
            raise GatewayError(500, "invalid_storage_path", "Chemin photo invalide") from error
        try:
            data = source.read_bytes()
        except OSError as error:
            raise GatewayError(503, "snapshot_unavailable", "Photo temporairement indisponible") from error
        if len(data) != int(row["size_bytes"]) or hashlib.sha256(data).hexdigest() != row["sha256"]:
            raise GatewayError(503, "snapshot_corrupted", "Photo corrompue")
        return data, self._snapshot_payload(row)

    def _expire_commands(self, now: int) -> None:
        self._database.execute(
            """UPDATE capture_commands SET status = 'expired'
               WHERE status IN ('queued', 'delivered') AND expires_at <= ?""",
            (now,),
        )

    def _register_camera(self) -> None:
        now = self._now_epoch()
        with self._write_lock:
            self._database.execute(
                """INSERT INTO cameras(id, name, zone_id, created_at)
                   VALUES (?, ?, ?, ?)
                   ON CONFLICT(id) DO UPDATE SET
                     name = excluded.name,
                     zone_id = excluded.zone_id""",
                (
                    self.config.camera_id,
                    self.config.camera_name.strip(),
                    self.config.zone_id,
                    now,
                ),
            )

    def _migrate(self) -> None:
        with self._write_lock:
            self._database.executescript(
                """
                CREATE TABLE IF NOT EXISTS gateway_meta (
                  key TEXT PRIMARY KEY,
                  value TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS cameras (
                  id TEXT PRIMARY KEY,
                  name TEXT NOT NULL,
                  zone_id TEXT NOT NULL,
                  last_seen_at INTEGER,
                  firmware_version TEXT,
                  rssi_dbm INTEGER,
                  free_heap_bytes INTEGER,
                  uptime_seconds INTEGER,
                  last_error TEXT,
                  created_at INTEGER NOT NULL
                );
                CREATE TABLE IF NOT EXISTS capture_commands (
                  id INTEGER PRIMARY KEY AUTOINCREMENT,
                  camera_id TEXT NOT NULL,
                  source TEXT NOT NULL,
                  requested_at INTEGER NOT NULL,
                  expires_at INTEGER NOT NULL,
                  delivered_at INTEGER,
                  completed_at INTEGER,
                  status TEXT NOT NULL,
                  snapshot_id TEXT,
                  FOREIGN KEY (camera_id) REFERENCES cameras(id) ON DELETE CASCADE,
                  CHECK (source IN ('app', 'telegram')),
                  CHECK (status IN ('queued', 'delivered', 'completed', 'expired', 'failed')),
                  CHECK (expires_at > requested_at)
                );
                CREATE TABLE IF NOT EXISTS camera_snapshots (
                  id TEXT PRIMARY KEY,
                  camera_id TEXT NOT NULL,
                  command_id INTEGER NOT NULL UNIQUE,
                  captured_at INTEGER NOT NULL,
                  stored_path TEXT NOT NULL UNIQUE,
                  sha256 TEXT NOT NULL,
                  size_bytes INTEGER NOT NULL,
                  created_at INTEGER NOT NULL,
                  FOREIGN KEY (camera_id) REFERENCES cameras(id) ON DELETE CASCADE,
                  FOREIGN KEY (command_id) REFERENCES capture_commands(id) ON DELETE RESTRICT,
                  CHECK (size_bytes > 0)
                );
                CREATE INDEX IF NOT EXISTS idx_capture_commands_camera_status
                  ON capture_commands(camera_id, status, id);
                CREATE INDEX IF NOT EXISTS idx_camera_snapshots_camera_captured
                  ON camera_snapshots(camera_id, captured_at DESC);
                """
            )

    def _json_body(self, body: bytes) -> dict[str, Any]:
        if len(body) > MAX_JSON_BYTES:
            raise GatewayError(413, "payload_too_large", "JSON trop volumineux")
        try:
            decoded = json.loads(body.decode("utf-8")) if body else {}
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise GatewayError(400, "invalid_json", "JSON invalide") from error
        if not isinstance(decoded, dict):
            raise GatewayError(400, "invalid_json", "Un objet JSON est requis")
        return decoded

    def _single_nonnegative_int(
        self,
        query: dict[str, list[str]],
        key: str,
        *,
        default: int | None = None,
    ) -> int:
        values = query.get(key)
        if values is None and default is not None:
            return default
        if values is None or len(values) != 1 or not values[0].isdigit():
            raise GatewayError(400, "invalid_query", f"Paramètre {key} invalide")
        value = int(values[0])
        if value > 2**63 - 1:
            raise GatewayError(400, "invalid_query", f"Paramètre {key} invalide")
        return value

    @staticmethod
    def _optional_text(value: Any, maximum: int) -> str | None:
        if value is None:
            return None
        if not isinstance(value, str) or not value.strip() or len(value.strip()) > maximum:
            raise GatewayError(422, "invalid_heartbeat", "Champ texte invalide")
        return value.strip()

    @staticmethod
    def _optional_int(value: Any, minimum: int, maximum: int) -> int | None:
        if value is None:
            return None
        if isinstance(value, bool) or not isinstance(value, int) or not minimum <= value <= maximum:
            raise GatewayError(422, "invalid_heartbeat", "Champ numérique invalide")
        return value

    @staticmethod
    def _command_payload(
        command_id: int,
        requested_at: int,
        expires_at: int,
        status: str,
    ) -> dict[str, Any]:
        return {
            "id": command_id,
            "type": "capture",
            "status": status,
            "requestedAt": CameraGatewayService._iso(requested_at),
            "expiresAt": CameraGatewayService._iso(expires_at),
            "expiresAtEpoch": expires_at,
        }

    @staticmethod
    def _snapshot_payload(row: sqlite3.Row) -> dict[str, Any]:
        return {
            "id": str(row["id"]),
            "capturedAt": CameraGatewayService._iso(int(row["captured_at"])),
            "sha256": str(row["sha256"]),
            "sizeBytes": int(row["size_bytes"]),
        }

    def _now_epoch(self) -> int:
        value = self._clock()
        if value.tzinfo is None:
            raise ValueError("L'horloge doit être timezone-aware")
        return int(value.timestamp())

    @staticmethod
    def _iso(epoch: int) -> str:
        return datetime.fromtimestamp(epoch, UTC).isoformat().replace("+00:00", "Z")

    @staticmethod
    def _request_id(raw: str | None) -> str:
        if raw and REQUEST_ID_RE.fullmatch(raw):
            return raw
        return uuid.uuid4().hex

    def _json_response(
        self,
        status: int,
        body: dict[str, Any],
        request_id: str,
        *,
        extra_headers: dict[str, str] | None = None,
    ) -> GatewayResponse:
        return GatewayResponse(
            status,
            body,
            self._security_headers(request_id, "application/json; charset=utf-8", extra_headers),
        )

    def _bytes_response(
        self,
        status: int,
        body: bytes,
        request_id: str,
        *,
        content_type: str,
        extra_headers: dict[str, str] | None = None,
    ) -> GatewayResponse:
        return GatewayResponse(
            status,
            body,
            self._security_headers(request_id, content_type, extra_headers),
        )

    def _error_response(self, error: GatewayError, request_id: str) -> GatewayResponse:
        headers = {"Retry-After": str(error.retry_after)} if error.retry_after else None
        return self._json_response(
            error.status,
            {
                "error": {
                    "code": error.code,
                    "message": error.message,
                    "retryable": error.status in {429, 503},
                },
                "requestId": request_id,
            },
            request_id,
            extra_headers=headers,
        )

    @staticmethod
    def _security_headers(
        request_id: str,
        content_type: str,
        extra: dict[str, str] | None,
    ) -> dict[str, str]:
        return {
            "Content-Type": content_type,
            "Cache-Control": "no-store",
            "X-Content-Type-Options": "nosniff",
            "X-Frame-Options": "DENY",
            "Referrer-Policy": "no-referrer",
            "X-Robots-Tag": "noindex, nofollow",
            "X-Request-ID": request_id,
            **(extra or {}),
        }

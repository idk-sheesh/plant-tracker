from __future__ import annotations

import base64
import hashlib
import hmac
import json
import math
import os
import re
import secrets
import sqlite3
import threading
import time
import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Callable, Iterable

from . import business


UTC = timezone.utc
API_PREFIX = "/api/v1"
DEVICE_TOKEN_PREFIX = "gt_dev_"
SESSION_TOKEN_PREFIX = "gt_sess_"
MAX_BODY_BYTES = 2 * 1024 * 1024
MAX_JSON_DEPTH = 12
MAX_BATCH_SIZE = 100
MAX_READINGS_PAGE = 500
MAX_IDENTIFIER_LENGTH = 80
MAX_EVENT_ID_LENGTH = 128
PASSWORD_MIN_LENGTH = 12
PASSWORD_MAX_LENGTH = 256
DEVICE_TOKEN_MAX_AGE_DAYS = 3650
TELEMETRY_MAX_AGE_DAYS = 31
TELEMETRY_MAX_FUTURE_SKEW = timedelta(minutes=5)
TEMPERATURE_MIN = -50.0
TEMPERATURE_MAX = 80.0
VPD_MIN = 0.0
VPD_MAX = 10.0
VPD_TOLERANCE = 0.25

IDENTIFIER_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.:-]{0,79}$")
EVENT_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$")
USERNAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{2,79}$")
MEASUREMENT_KEY_RE = re.compile(r"^[A-Za-z][A-Za-z0-9_.-]{0,79}$")


class ApiError(Exception):
    def __init__(
        self,
        status: int,
        code: str,
        message: str,
        *,
        details: list[dict[str, Any]] | None = None,
        retryable: bool = False,
    ) -> None:
        super().__init__(message)
        self.status = status
        self.code = code
        self.message = message
        self.details = details or []
        self.retryable = retryable


@dataclass(frozen=True)
class ApiResponse:
    status: int
    body: dict[str, Any]
    headers: dict[str, str]


@dataclass(frozen=True)
class AuthenticatedUser:
    id: str
    username: str
    session_hash: str
    scope: str = "full"


@dataclass(frozen=True)
class AuthenticatedDevice:
    id: str
    owner_user_id: str
    credential_id: str


class SlidingWindowLimiter:
    def __init__(self, limit: int = 120, window_seconds: int = 60) -> None:
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
            if len(self._events) > 10000:
                self._events = {
                    item_key: item_events
                    for item_key, item_events in self._events.items()
                    if item_events
                }
            return True


class CloudService:
    """HTTP-independent API core.

    Keeping routing and persistence here makes the security-sensitive behavior
    testable without opening a network listener. `server.py` only supplies the
    HTTPS transport.
    """

    def __init__(
        self,
        database_path: str | Path = ":memory:",
        *,
        clock: Callable[[], datetime] | None = None,
        max_body_bytes: int = MAX_BODY_BYTES,
        allow_registration: bool = True,
    ) -> None:
        self.database_path = str(database_path)
        self.max_body_bytes = max_body_bytes
        self.allow_registration = allow_registration
        self._clock = clock or (lambda: datetime.now(UTC))
        self._write_lock = threading.RLock()
        self._limiter = SlidingWindowLimiter()
        self._failed_login_limiter = SlidingWindowLimiter(limit=10, window_seconds=300)
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

    def close(self) -> None:
        self._database.close()

    def backup(self, destination: str | Path) -> None:
        """Create a consistent SQLite backup without exposing app secrets."""
        destination_path = Path(destination)
        destination_path.parent.mkdir(parents=True, exist_ok=True)
        target = sqlite3.connect(str(destination_path))
        try:
            with target:
                self._database.backup(target)
        finally:
            target.close()

    def rotate_device_token_for_local_admin(self, device_id: str) -> str:
        """Rotate a credential from a trusted local maintenance process.

        The raw token is returned once and is never persisted by the API.
        """
        if not IDENTIFIER_RE.fullmatch(device_id):
            raise ValueError("Identifiant appareil invalide")
        device = self._database.execute(
            "SELECT id FROM devices WHERE id = ? AND status = 'active'",
            (device_id,),
        ).fetchone()
        if device is None:
            raise ValueError("Appareil actif introuvable")
        raw_token, token_hint, token_hash = _new_device_token()
        now = self._now_iso()
        request_id = self._request_id(None)
        with self._write_lock, self._database:
            self._database.execute(
                "UPDATE device_credentials SET revoked_at = ?, rotated_at = ? "
                "WHERE device_id = ? AND revoked_at IS NULL",
                (now, now, device_id),
            )
            self._database.execute(
                "INSERT INTO device_credentials(id, device_id, token_hint, token_hash, created_at) "
                "VALUES (?, ?, ?, ?, ?)",
                (self._public_id("cred_"), device_id, token_hint, token_hash, now),
            )
            self._audit(
                "system",
                None,
                "device_token_rotated_local",
                device_id,
                request_id,
            )
        return raw_token

    def reset_user_password_for_local_admin(self, username: str) -> str:
        """Replace a user's password and revoke every existing session."""
        if not isinstance(username, str) or not USERNAME_RE.fullmatch(username):
            raise ValueError("Nom d’utilisateur invalide")
        user = self._database.execute(
            "SELECT id FROM users WHERE username = ? AND disabled_at IS NULL",
            (username.lower(),),
        ).fetchone()
        if user is None:
            raise ValueError("Utilisateur actif introuvable")
        raw_password = secrets.token_urlsafe(24).rstrip("=") + "-Aa1!"
        password_hash = _scrypt_hash(raw_password)
        now = self._now_iso()
        request_id = self._request_id(None)
        with self._write_lock, self._database:
            self._database.execute(
                "UPDATE users SET password_hash = ? WHERE id = ?",
                (password_hash, user["id"]),
            )
            self._database.execute(
                "UPDATE user_sessions SET revoked_at = COALESCE(revoked_at, ?) "
                "WHERE user_id = ?",
                (now, user["id"]),
            )
            self._audit(
                "system",
                None,
                "user_password_reset_local",
                user["id"],
                request_id,
            )
        return raw_password

    def handle(
        self,
        method: str,
        path: str,
        *,
        headers: dict[str, str] | None = None,
        body: bytes = b"",
        remote_ip: str = "unknown",
    ) -> ApiResponse:
        request_headers = {key.lower(): value for key, value in (headers or {}).items()}
        request_id = self._request_id(request_headers.get("x-request-id"))
        if len(body) > self.max_body_bytes:
            return self._error_response(
                ApiError(413, "payload_too_large", "Requête trop volumineuse"),
                request_id,
            )
        if not self._limiter.allow(f"ip:{remote_ip}"):
            return self._error_response(
                ApiError(429, "rate_limited", "Trop de requêtes", retryable=True),
                request_id,
            )

        parsed_path, query = self._split_path(path)
        try:
            if method.upper() == "OPTIONS":
                raise ApiError(405, "method_not_allowed", "Méthode non autorisée")
            if parsed_path == f"{API_PREFIX}/health" and method.upper() == "GET":
                return self._success_response(
                    {"status": "ok", "version": "1.1", "requestId": request_id}, request_id
                )
            if parsed_path == "/robots.txt" and method.upper() == "GET":
                return self._success_response(
                    {"content": "User-agent: *\nDisallow: /\n"}, request_id
                )

            payload = self._json_body(body) if body else {}
            # CloudService owns one SQLite connection while the HTTP transport
            # is threaded. Serialize every database-backed dispatch on that
            # connection; nested write sections use the same reentrant lock.
            with self._write_lock:
                result = self._dispatch(
                    method.upper(),
                    parsed_path,
                    query,
                    request_headers,
                    payload,
                    remote_ip,
                    request_id,
                )
            return self._success_response(result, request_id)
        except ApiError as error:
            return self._error_response(error, request_id)
        except sqlite3.IntegrityError:
            self._safe_audit("system", None, "database_integrity_error", None, request_id)
            return self._error_response(
                ApiError(409, "conflict", "Opération en conflit"), request_id
            )
        except sqlite3.Error:
            self._safe_audit("system", None, "database_error", None, request_id)
            return self._error_response(
                ApiError(503, "temporary_database_error", "Service temporairement indisponible", retryable=True),
                request_id,
            )
        except Exception:
            self._safe_audit("system", None, "internal_error", None, request_id)
            return self._error_response(
                ApiError(500, "internal_error", "Erreur interne"), request_id
            )

    def _dispatch(
        self,
        method: str,
        path: str,
        query: dict[str, str],
        headers: dict[str, str],
        payload: dict[str, Any],
        remote_ip: str,
        request_id: str,
    ) -> dict[str, Any]:
        if path == f"{API_PREFIX}/auth/register" and method == "POST":
            return self._register(payload, request_id)
        if path == f"{API_PREFIX}/auth/login" and method == "POST":
            return self._login(payload, request_id, remote_ip)
        if path == f"{API_PREFIX}/auth/logout" and method == "POST":
            user = self._require_user(headers, remote_ip)
            return self._logout(user, request_id)
        if path == f"{API_PREFIX}/me" and method == "GET":
            user = self._require_user(headers, remote_ip)
            return {"id": user.id, "username": user.username, "scope": user.scope}

        if path in (f"{API_PREFIX}/sync/status", f"{API_PREFIX}/plants",
                    f"{API_PREFIX}/actions", f"{API_PREFIX}/stats") or path.startswith(f"{API_PREFIX}/plants/"):
            user = self._require_user(headers, remote_ip)
            if path == f"{API_PREFIX}/sync/status" and method == "GET":
                return business.sync_status(self._database, user.id)
            if path == f"{API_PREFIX}/plants" and method == "GET":
                try:
                    return business.list_plants(self._database, user.id, query)
                except business.BusinessValidationError as exc:
                    raise ApiError(400, "invalid_query", str(exc)) from exc
            if path.startswith(f"{API_PREFIX}/plants/") and method == "GET":
                plant_id = path.removeprefix(f"{API_PREFIX}/plants/")
                if not IDENTIFIER_RE.fullmatch(plant_id):
                    raise ApiError(404, "not_found", "Ressource introuvable")
                result = business.plant_detail(self._database, user.id, plant_id)
                if result is None:
                    raise ApiError(404, "not_found", "Ressource introuvable")
                return result
            if path == f"{API_PREFIX}/actions" and method == "GET":
                try:
                    return business.list_actions(self._database, user.id, query)
                except business.BusinessValidationError as exc:
                    raise ApiError(400, "invalid_query", str(exc)) from exc
            if path == f"{API_PREFIX}/stats" and method == "GET":
                return business.stats(self._database, user.id, self._now())
            raise ApiError(405, "method_not_allowed", "Méthode non autorisée")
        if path == f"{API_PREFIX}/sync/snapshot":
            user = self._require_user(headers, remote_ip)
            if method != "POST":
                raise ApiError(405, "method_not_allowed", "Méthode non autorisée")
            self._require_full_scope(user)
            try:
                with self._write_lock, self._database:
                    result = business.publish(self._database, user.id, payload, self._now_iso())
                    self._audit("user", user.id, "business_snapshot_published", user.id, request_id,
                                {"plant_count": result["plantCount"], "action_count": result["actionCount"]})
                return result
            except business.BusinessValidationError as exc:
                raise ApiError(400, "invalid_snapshot", str(exc)) from exc

        device_path = self._device_path(path)
        if device_path is not None:
            device_id, suffix = device_path
            if suffix == "telemetry" and method == "POST":
                device = self._require_device(headers, remote_ip)
                if device.id != device_id:
                    raise ApiError(403, "forbidden", "Accès refusé")
                return self._ingest_telemetry(device, payload, request_id, remote_ip)

            user = self._require_user(headers, remote_ip)
            device = self._owned_device(user, device_id)
            if suffix == "" and method == "GET":
                return self._device_json(device)
            if suffix == "" and method == "DELETE":
                self._require_full_scope(user)
                return self._delete_device(user, device_id, request_id)
            if suffix == "readings" and method == "GET":
                return self._readings(device, query)
            if suffix == "chart" and method == "GET":
                return self._chart(device, query)
            if suffix == "latest" and method == "GET":
                return self._latest(device)
            if suffix == "backfill" and method == "POST":
                self._require_full_scope(user)
                if device["status"] != "active":
                    raise ApiError(409, "device_not_active", "Appareil cloud non actif")
                return self._ingest_telemetry(
                    AuthenticatedDevice(device["id"], user.id, ""),
                    payload,
                    request_id,
                    remote_ip,
                    source="app-backfill",
                    actor_type="user",
                )
            if suffix == "rotate-token" and method == "POST":
                self._require_full_scope(user)
                return self._rotate_device_token(user, device, request_id)
            if suffix == "revoke" and method == "POST":
                self._require_full_scope(user)
                return self._revoke_device(user, device, request_id)

        if path == f"{API_PREFIX}/devices" and method == "GET":
            user = self._require_user(headers, remote_ip)
            return {
                "devices": [
                    self._device_json(row)
                    for row in self._database.execute(
                        "SELECT * FROM devices WHERE owner_user_id = ? ORDER BY created_at ASC",
                        (user.id,),
                    ).fetchall()
                ]
            }
        if path == f"{API_PREFIX}/devices" and method == "POST":
            user = self._require_user(headers, remote_ip)
            self._require_full_scope(user)
            return self._create_device(user, payload, request_id)
        raise ApiError(404, "not_found", "Ressource introuvable")

    def _register(self, payload: dict[str, Any], request_id: str) -> dict[str, Any]:
        self._strict_keys(payload, {"username", "password"})
        username = self._required_text(payload.get("username"), "username", USERNAME_RE)
        password = self._password(payload.get("password"))
        user_id = self._public_id("usr_")
        now = self._now_iso()
        password_hash = _scrypt_hash(password)
        try:
            with self._write_lock, self._database:
                if not self.allow_registration and self._database.execute(
                    "SELECT 1 FROM users LIMIT 1"
                ).fetchone() is not None:
                    raise ApiError(
                        403,
                        "registration_closed",
                        "Inscription fermée",
                    )
                self._database.execute(
                    "INSERT INTO users(id, username, password_hash, created_at) VALUES (?, ?, ?, ?)",
                    (user_id, username.lower(), password_hash, now),
                )
                self._audit("system", None, "user_registered", user_id, request_id)
        except sqlite3.IntegrityError:
            raise ApiError(409, "registration_unavailable", "Inscription impossible")
        return {"status": "created", "userId": user_id, "requestId": request_id}

    def _login(
        self,
        payload: dict[str, Any],
        request_id: str,
        remote_ip: str,
    ) -> dict[str, Any]:
        self._strict_keys(payload, {"username", "password", "scope"})
        username = self._required_text(payload.get("username"), "username", USERNAME_RE)
        password = self._password(payload.get("password"))
        scope = payload.get("scope", "full")
        if scope not in ("full", "gardenjournal.read"):
            raise ApiError(400, "invalid_scope", "Portée invalide")
        login_key = f"login:{remote_ip}:{username.lower()}"
        row = self._database.execute(
            "SELECT * FROM users WHERE username = ? AND disabled_at IS NULL",
            (username.lower(),),
        ).fetchone()
        valid = row is not None and _scrypt_verify(password, row["password_hash"])
        if not valid:
            self._safe_audit("anonymous", None, "login_failed", None, request_id)
            if not self._failed_login_limiter.allow(login_key):
                raise ApiError(429, "rate_limited", "Trop de tentatives", retryable=True)
            raise ApiError(401, "invalid_credentials", "Identifiants invalides")
        if not self._limiter.allow(f"user-login:{row['id']}:{remote_ip}"):
            raise ApiError(429, "rate_limited", "Trop de tentatives", retryable=True)
        raw_token = _random_token(SESSION_TOKEN_PREFIX)
        expires = self._now() + timedelta(hours=12)
        token_hash = _sha256(raw_token)
        with self._write_lock, self._database:
            self._database.execute(
                "INSERT INTO user_sessions(id, user_id, token_hash, expires_at, created_at, last_used_at, scope) "
                "VALUES (?, ?, ?, ?, ?, ?, ?)",
                (
                    self._public_id("ses_"),
                    row["id"],
                    token_hash,
                    expires.isoformat(),
                    self._now_iso(),
                    self._now_iso(),
                    scope,
                ),
            )
            self._audit("user", row["id"], "login_succeeded", row["id"], request_id)
        return {
            "status": "authenticated",
            "sessionToken": raw_token,
            "expiresAt": expires.isoformat(),
            "scope": scope,
            "requestId": request_id,
        }

    def _logout(self, user: AuthenticatedUser, request_id: str) -> dict[str, Any]:
        with self._write_lock, self._database:
            self._database.execute(
                "UPDATE user_sessions SET revoked_at = ? WHERE token_hash = ?",
                (self._now_iso(), user.session_hash),
            )
            self._audit("user", user.id, "logout", user.id, request_id)
        return {"status": "logged_out", "requestId": request_id}

    def _create_device(
        self,
        user: AuthenticatedUser,
        payload: dict[str, Any],
        request_id: str,
    ) -> dict[str, Any]:
        self._strict_keys(payload, {"name", "firmwareVersion"})
        name = self._optional_text(payload.get("name"), "name", 80) or "ESP32"
        firmware = self._optional_text(payload.get("firmwareVersion"), "firmwareVersion", 80)
        device_id = self._public_id("dev_")
        raw_token, token_hint, token_hash = _new_device_token()
        now = self._now_iso()
        with self._write_lock, self._database:
            self._database.execute(
                "INSERT INTO devices(id, owner_user_id, name, firmware_version, status, created_at) "
                "VALUES (?, ?, ?, ?, 'active', ?)",
                (device_id, user.id, name, firmware, now),
            )
            self._database.execute(
                "INSERT INTO device_credentials(id, device_id, token_hint, token_hash, created_at) "
                "VALUES (?, ?, ?, ?, ?)",
                (self._public_id("cred_"), device_id, token_hint, token_hash, now),
            )
            self._database.execute(
                "INSERT INTO device_sync_state(device_id) VALUES (?)", (device_id,)
            )
            self._audit("user", user.id, "device_provisioned", device_id, request_id)
        return {
            "status": "created",
            "device": self._device_json(
                self._database.execute(
                    "SELECT * FROM devices WHERE id = ?", (device_id,)
                ).fetchone()
            ),
            "deviceToken": raw_token,
            "tokenShownOnce": True,
            "requestId": request_id,
        }

    def _rotate_device_token(
        self,
        user: AuthenticatedUser,
        device: sqlite3.Row,
        request_id: str,
    ) -> dict[str, Any]:
        raw_token, token_hint, token_hash = _new_device_token()
        now = self._now_iso()
        with self._write_lock, self._database:
            self._database.execute(
                "UPDATE device_credentials SET revoked_at = ?, rotated_at = ? "
                "WHERE device_id = ? AND revoked_at IS NULL",
                (now, now, device["id"]),
            )
            self._database.execute(
                "INSERT INTO device_credentials(id, device_id, token_hint, token_hash, created_at) "
                "VALUES (?, ?, ?, ?, ?)",
                (self._public_id("cred_"), device["id"], token_hint, token_hash, now),
            )
            self._audit("user", user.id, "device_token_rotated", device["id"], request_id)
        return {
            "status": "rotated",
            "deviceId": device["id"],
            "deviceToken": raw_token,
            "tokenShownOnce": True,
            "requestId": request_id,
        }

    def _revoke_device(
        self,
        user: AuthenticatedUser,
        device: sqlite3.Row,
        request_id: str,
    ) -> dict[str, Any]:
        now = self._now_iso()
        with self._write_lock, self._database:
            self._database.execute(
                "UPDATE devices SET status = 'revoked', updated_at = ? WHERE id = ?",
                (now, device["id"]),
            )
            self._database.execute(
                "UPDATE device_credentials SET revoked_at = ? WHERE device_id = ? AND revoked_at IS NULL",
                (now, device["id"]),
            )
            self._audit("user", user.id, "device_revoked", device["id"], request_id)
        return {"status": "revoked", "deviceId": device["id"], "requestId": request_id}

    def _delete_device(
        self,
        user: AuthenticatedUser,
        device_id: str,
        request_id: str,
    ) -> dict[str, Any]:
        with self._write_lock, self._database:
            self._database.execute("DELETE FROM devices WHERE id = ?", (device_id,))
            self._audit("user", user.id, "device_deleted", device_id, request_id)
        return {"status": "deleted", "deviceId": device_id, "requestId": request_id}

    def _ingest_telemetry(
        self,
        device: AuthenticatedDevice,
        payload: dict[str, Any],
        request_id: str,
        remote_ip: str,
        *,
        source: str = "device",
        actor_type: str = "device",
    ) -> dict[str, Any]:
        self._strict_keys(
            payload,
            {
                "schema",
                "schemaVersion",
                "deviceId",
                "firmwareVersion",
                "readings",
                "eventId",
                "sequence",
                "measuredAt",
                "timestamp",
                "temperatureC",
                "temperature",
                "humidityPercent",
                "humidity",
                "vpdKpa",
                "vpd",
                "capabilities",
                "measurements",
                "metrics",
            },
        )
        version = payload.get("schemaVersion", payload.get("schema", 1))
        if version != 1:
            raise ApiError(422, "unsupported_schema", "Version d’événement non supportée")
        body_device_id = payload.get("deviceId")
        if body_device_id is not None and body_device_id != device.id:
            raise ApiError(403, "forbidden", "Accès refusé")
        raw_events = payload.get("readings")
        if raw_events is None:
            raw_events = [payload]
        if not isinstance(raw_events, list) or not raw_events:
            raise ApiError(422, "invalid_readings", "Aucune mesure valide")
        if len(raw_events) > MAX_BATCH_SIZE:
            raise ApiError(413, "batch_too_large", "Lot de mesures trop volumineux")

        accepted_ids: list[str] = []
        rejected: list[dict[str, Any]] = []
        now = self._now()
        with self._write_lock:
            self._database.execute("BEGIN IMMEDIATE")
            try:
                for raw_event in raw_events:
                    try:
                        normalized = self._validate_event(raw_event, device.id, now)
                        outcome = self._store_event(device.id, normalized, now, source)
                        if outcome in {"accepted", "duplicate"}:
                            accepted_ids.append(normalized["event_id"])
                        if outcome == "conflict_event":
                            raise ApiError(409, "event_id_conflict", "Événement en conflit")
                        if outcome == "conflict_sequence":
                            raise ApiError(409, "sequence_conflict", "Séquence en conflit")
                    except ApiError as error:
                        event_id = raw_event.get("eventId") if isinstance(raw_event, dict) else None
                        sequence = raw_event.get("sequence") if isinstance(raw_event, dict) else None
                        rejected.append(
                            {
                                "eventId": event_id if isinstance(event_id, str) else None,
                                "sequence": sequence if isinstance(sequence, int) else None,
                                "code": error.code,
                                "retryable": error.retryable,
                            }
                        )
                accepted_through = self._advance_accepted_through(device.id)
                self._database.execute(
                    "UPDATE devices SET firmware_version = COALESCE(?, firmware_version), "
                    "last_contact_at = ?, updated_at = ? WHERE id = ?",
                    (
                        self._optional_text(payload.get("firmwareVersion"), "firmwareVersion", 80),
                        now.isoformat(),
                        now.isoformat(),
                        device.id,
                    ),
                )
                if device.credential_id:
                    self._database.execute(
                        "UPDATE device_credentials SET last_used_at = ? WHERE id = ?",
                        (now.isoformat(), device.credential_id),
                    )
                self._database.execute(
                    "UPDATE device_sync_state SET last_contact_at = ?, last_error = NULL WHERE device_id = ?",
                    (now.isoformat(), device.id),
                )
                self._database.commit()
            except Exception:
                self._database.rollback()
                raise

        status = "accepted" if not rejected else "partial" if accepted_ids else "rejected"
        self._audit(
            actor_type,
            device.owner_user_id if actor_type == "user" else device.id,
            "telemetry_ingested",
            device.id,
            request_id,
            {"accepted": len(accepted_ids), "rejected": len(rejected)},
        )
        return {
            "status": status,
            "acceptedThrough": accepted_through,
            "acceptedEventIds": accepted_ids,
            "rejected": rejected,
            "serverTime": now.isoformat(),
            "requestId": request_id,
        }

    def _validate_event(
        self,
        raw_event: Any,
        device_id: str,
        now: datetime,
    ) -> dict[str, Any]:
        if not isinstance(raw_event, dict):
            raise ApiError(422, "invalid_event", "Événement invalide")
        self._strict_keys(
            raw_event,
            {
                "deviceId",
                "eventId",
                "sequence",
                "measuredAt",
                "timestamp",
                "temperatureC",
                "temperature",
                "humidityPercent",
                "humidity",
                "vpdKpa",
                "vpd",
                "capabilities",
                "measurements",
                "metrics",
            },
        )
        if raw_event.get("deviceId") not in (None, device_id):
            raise ApiError(403, "forbidden", "Accès refusé")
        event_id = raw_event.get("eventId")
        if not isinstance(event_id, str) or not EVENT_ID_RE.fullmatch(event_id):
            raise ApiError(422, "invalid_event_id", "Identifiant d’événement invalide")
        sequence = raw_event.get("sequence")
        if isinstance(sequence, bool) or not isinstance(sequence, int) or sequence <= 0:
            raise ApiError(422, "invalid_sequence", "Séquence invalide")
        measured_at = _parse_timestamp(raw_event.get("measuredAt", raw_event.get("timestamp")))
        if measured_at < now - timedelta(days=TELEMETRY_MAX_AGE_DAYS):
            raise ApiError(422, "timestamp_too_old", "Horodatage trop ancien")
        if measured_at > now + TELEMETRY_MAX_FUTURE_SKEW:
            raise ApiError(422, "timestamp_in_future", "Horodatage futur")
        temperature = _finite_number(
            raw_event.get("temperatureC", raw_event.get("temperature")),
            "temperatureC",
        )
        humidity = _finite_number(
            raw_event.get("humidityPercent", raw_event.get("humidity")),
            "humidityPercent",
        )
        if not TEMPERATURE_MIN <= temperature <= TEMPERATURE_MAX:
            raise ApiError(422, "temperature_out_of_range", "Température hors limites")
        if not 0 <= humidity <= 100:
            raise ApiError(422, "humidity_out_of_range", "Humidité hors limites")
        calculated_vpd = _calculate_vpd(temperature, humidity)
        received_vpd_raw = raw_event.get("vpdKpa", raw_event.get("vpd"))
        received_vpd = None
        if received_vpd_raw is not None:
            received_vpd = _finite_number(received_vpd_raw, "vpdKpa")
            if not VPD_MIN <= received_vpd <= VPD_MAX:
                raise ApiError(422, "vpd_out_of_range", "VPD hors limites")
            if abs(received_vpd - calculated_vpd) > VPD_TOLERANCE:
                raise ApiError(422, "vpd_mismatch", "VPD incohérent")
        capabilities = _normalize_capabilities(raw_event.get("capabilities"))
        measurements = _normalize_measurements(
            raw_event.get("measurements", raw_event.get("metrics")),
            capabilities,
        )
        return {
            "event_id": event_id,
            "sequence": sequence,
            "measured_at": measured_at.isoformat(),
            "temperature_c": round(temperature, 4),
            "humidity_percent": round(humidity, 4),
            "vpd_received": None if received_vpd is None else round(received_vpd, 4),
            "vpd_calculated": round(calculated_vpd, 4),
            "capabilities": capabilities,
            "measurements": measurements,
        }

    def _store_event(
        self,
        device_id: str,
        event: dict[str, Any],
        now: datetime,
        source: str,
    ) -> str:
        encoded = json.dumps(event, sort_keys=True, separators=(",", ":"))
        payload_hash = hashlib.sha256(encoded.encode("utf-8")).hexdigest()
        by_event = self._database.execute(
            "SELECT payload_hash FROM telemetry_events WHERE device_id = ? AND event_id = ?",
            (device_id, event["event_id"]),
        ).fetchone()
        if by_event is not None:
            return "duplicate" if hmac.compare_digest(by_event["payload_hash"], payload_hash) else "conflict_event"
        by_sequence = self._database.execute(
            "SELECT event_id FROM telemetry_events WHERE device_id = ? AND sequence = ?",
            (device_id, event["sequence"]),
        ).fetchone()
        if by_sequence is not None:
            return "conflict_sequence"
        self._database.execute(
            """INSERT INTO telemetry_events(
                device_id, event_id, sequence, source, measured_at, temperature_c,
                humidity_percent, vpd_received, vpd_calculated, payload_hash,
                received_at, capabilities_json, measurements_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (
                device_id,
                event["event_id"],
                event["sequence"],
                source,
                event["measured_at"],
                event["temperature_c"],
                event["humidity_percent"],
                event["vpd_received"],
                event["vpd_calculated"],
                payload_hash,
                now.isoformat(),
                json.dumps(event["capabilities"], sort_keys=True, separators=(",", ":")),
                json.dumps(event["measurements"], sort_keys=True, separators=(",", ":")),
            ),
        )
        return "accepted"

    def _advance_accepted_through(self, device_id: str) -> int:
        row = self._database.execute(
            "SELECT accepted_through FROM device_sync_state WHERE device_id = ?",
            (device_id,),
        ).fetchone()
        accepted = int(row["accepted_through"] if row else 0)
        while self._database.execute(
            "SELECT 1 FROM telemetry_events WHERE device_id = ? AND source = 'device' AND sequence = ?",
            (device_id, accepted + 1),
        ).fetchone():
            accepted += 1
        self._database.execute(
            """UPDATE device_sync_state SET accepted_through = ?, max_sequence = (
                SELECT COALESCE(MAX(sequence), 0) FROM telemetry_events WHERE device_id = ? AND source = 'device'
            ) WHERE device_id = ?""",
            (accepted, device_id, device_id),
        )
        return accepted

    def _readings(self, device: sqlite3.Row, query: dict[str, str]) -> dict[str, Any]:
        since = _positive_int_or_zero(query.get("since"), "since")
        limit = _positive_int_or_default(query.get("limit"), MAX_READINGS_PAGE)
        limit = min(limit, MAX_READINGS_PAGE)
        cursor = _decode_cursor(query.get("cursor"))
        clauses = ["device_id = ?"]
        args: list[Any] = [device["id"]]
        # Le curseur d'ingestion est l'unique critère de reprise. `since` sert
        # seulement à borner une première synchronisation sans curseur.
        if cursor is None and since:
            clauses.append("CAST(strftime('%s', measured_at) AS INTEGER) > ?")
            args.append(since)
        if cursor is not None:
            clauses.append("id > ?")
            args.append(cursor)
        rows = self._database.execute(
            "SELECT * FROM telemetry_events WHERE "
            + " AND ".join(clauses)
            + " ORDER BY id ASC LIMIT ?",
            (*args, limit),
        ).fetchall()
        next_cursor = (
            _encode_cursor(rows[-1]["id"])
            if rows
            else (_encode_cursor(cursor) if cursor is not None else None)
        )
        return {
            "schema": 1,
            "deviceId": device["id"],
            "lastContactAt": device["last_contact_at"],
            "nextCursor": next_cursor,
            "readings": [self._event_json(row) for row in rows],
        }

    def _latest(self, device: sqlite3.Row) -> dict[str, Any]:
        row = self._database.execute(
            "SELECT * FROM telemetry_events WHERE device_id = ? "
            "ORDER BY measured_at DESC, id DESC LIMIT 1",
            (device["id"],),
        ).fetchone()
        if row is None:
            raise ApiError(404, "no_readings", "Aucune mesure disponible")
        return self._event_json(row)

    def _chart(self, device: sqlite3.Row, query: dict[str, str]) -> dict[str, Any]:
        if set(query) != {"hours"} or query["hours"] not in ("24", "168", "720"):
            raise ApiError(400, "invalid_query", "Plage temporelle invalide")
        hours = int(query["hours"])
        since = (self._now() - timedelta(hours=hours)).isoformat()
        rows = self._database.execute(
            "SELECT * FROM telemetry_events WHERE device_id = ? AND measured_at >= ? "
            "ORDER BY measured_at DESC, id DESC LIMIT 401", (device["id"], since)
        ).fetchall()
        truncated = len(rows) > 400
        return {"deviceId": device["id"], "hours": hours,
                "lastContactAt": device["last_contact_at"], "truncated": truncated,
                "readings": [self._event_json(row) for row in reversed(rows[:400])]}

    def _event_json(self, row: sqlite3.Row) -> dict[str, Any]:
        timestamp = datetime.fromisoformat(row["measured_at"]).astimezone(UTC)
        return {
            "schemaVersion": 1,
            "deviceId": row["device_id"],
            "eventId": row["event_id"],
            "sequence": row["sequence"],
            "measuredAt": timestamp.isoformat().replace("+00:00", "Z"),
            "timestamp": int(timestamp.timestamp()),
            "temperatureC": row["temperature_c"],
            "temperature": row["temperature_c"],
            "humidityPercent": row["humidity_percent"],
            "humidity": row["humidity_percent"],
            "vpdKpa": row["vpd_calculated"],
            "vpd": row["vpd_calculated"],
            "serverVpd": row["vpd_calculated"],
            "source": row["source"],
            "capabilities": json.loads(row["capabilities_json"] or "{}"),
            "measurements": json.loads(row["measurements_json"] or "{}"),
        }

    def _require_user(
        self,
        headers: dict[str, str],
        remote_ip: str,
    ) -> AuthenticatedUser:
        raw_token = _bearer(headers.get("authorization"), SESSION_TOKEN_PREFIX)
        token_hash = _sha256(raw_token)
        row = self._database.execute(
            "SELECT users.id, users.username, user_sessions.token_hash, user_sessions.expires_at, user_sessions.scope "
            "FROM user_sessions JOIN users ON users.id = user_sessions.user_id "
            "WHERE user_sessions.token_hash = ? AND user_sessions.revoked_at IS NULL "
            "AND users.disabled_at IS NULL",
            (token_hash,),
        ).fetchone()
        if row is None:
            raise ApiError(401, "unauthorized", "Authentification requise")
        expires = datetime.fromisoformat(row["expires_at"])
        if expires <= self._now():
            raise ApiError(401, "unauthorized", "Authentification requise")
        if not self._limiter.allow(f"user:{row['id']}:{remote_ip}"):
            raise ApiError(429, "rate_limited", "Trop de requêtes", retryable=True)
        self._database.execute(
            "UPDATE user_sessions SET last_used_at = ? WHERE token_hash = ?",
            (self._now_iso(), token_hash),
        )
        return AuthenticatedUser(row["id"], row["username"], row["token_hash"], row["scope"])

    @staticmethod
    def _require_full_scope(user: AuthenticatedUser) -> None:
        if user.scope != "full":
            raise ApiError(403, "forbidden", "Lecture seule")

    def _require_device(
        self,
        headers: dict[str, str],
        remote_ip: str,
    ) -> AuthenticatedDevice:
        raw_token = _bearer(headers.get("authorization"), DEVICE_TOKEN_PREFIX)
        hint = raw_token.split(".", 1)[0]
        rows = self._database.execute(
            "SELECT device_credentials.*, devices.owner_user_id, devices.status "
            "FROM device_credentials JOIN devices ON devices.id = device_credentials.device_id "
            "WHERE token_hint = ? AND revoked_at IS NULL AND devices.status = 'active'",
            (hint,),
        ).fetchall()
        for row in rows:
            if _scrypt_verify(raw_token, row["token_hash"]):
                if not self._limiter.allow(f"device:{row['device_id']}"):
                    raise ApiError(429, "rate_limited", "Trop de requêtes", retryable=True)
                return AuthenticatedDevice(
                    row["device_id"], row["owner_user_id"], row["id"]
                )
        raise ApiError(401, "unauthorized", "Authentification requise")

    def _owned_device(self, user: AuthenticatedUser, device_id: str) -> sqlite3.Row:
        if not IDENTIFIER_RE.fullmatch(device_id):
            raise ApiError(404, "not_found", "Ressource introuvable")
        row = self._database.execute(
            "SELECT * FROM devices WHERE id = ? AND owner_user_id = ?",
            (device_id, user.id),
        ).fetchone()
        if row is None:
            raise ApiError(404, "not_found", "Ressource introuvable")
        return row

    def _device_json(self, row: sqlite3.Row) -> dict[str, Any]:
        return {
            "id": row["id"],
            "name": row["name"],
            "firmwareVersion": row["firmware_version"],
            "status": row["status"],
            "createdAt": row["created_at"],
            "lastContactAt": row["last_contact_at"],
            "acceptedThrough": self._accepted_through(row["id"]),
        }

    def _accepted_through(self, device_id: str) -> int:
        row = self._database.execute(
            "SELECT accepted_through FROM device_sync_state WHERE device_id = ?",
            (device_id,),
        ).fetchone()
        return int(row["accepted_through"] if row else 0)

    def _strict_keys(self, payload: dict[str, Any], allowed: set[str]) -> None:
        if not isinstance(payload, dict):
            raise ApiError(400, "invalid_json", "Objet JSON attendu")
        unknown = set(payload) - allowed
        if unknown:
            raise ApiError(422, "unknown_fields", "Champs non autorisés")

    def _password(self, value: Any) -> str:
        if not isinstance(value, str) or not PASSWORD_MIN_LENGTH <= len(value) <= PASSWORD_MAX_LENGTH:
            raise ApiError(422, "invalid_password", "Mot de passe invalide")
        return value

    def _required_text(
        self,
        value: Any,
        name: str,
        pattern: re.Pattern[str],
    ) -> str:
        if not isinstance(value, str) or not pattern.fullmatch(value):
            raise ApiError(422, f"invalid_{name}", f"{name} invalide")
        return value

    def _optional_text(self, value: Any, name: str, maximum: int) -> str | None:
        if value is None:
            return None
        if not isinstance(value, str) or not value.strip() or len(value.strip()) > maximum:
            raise ApiError(422, f"invalid_{name}", f"{name} invalide")
        return value.strip()

    def _json_body(self, body: bytes) -> dict[str, Any]:
        if len(body) > self.max_body_bytes:
            raise ApiError(413, "payload_too_large", "Requête trop volumineuse")
        try:
            parsed = json.loads(
                body.decode("utf-8"),
                parse_constant=lambda value: (_ for _ in ()).throw(ValueError(value)),
            )
        except (UnicodeDecodeError, ValueError, json.JSONDecodeError):
            raise ApiError(400, "invalid_json", "JSON invalide")
        if not isinstance(parsed, dict):
            raise ApiError(400, "invalid_json", "Objet JSON attendu")
        if _json_depth(parsed) > MAX_JSON_DEPTH:
            raise ApiError(413, "json_too_deep", "JSON trop imbriquÃ©")
        return parsed

    def _split_path(self, path: str) -> tuple[str, dict[str, str]]:
        raw_path, _, raw_query = path.partition("?")
        query: dict[str, str] = {}
        for pair in raw_query.split("&") if raw_query else []:
            key, _, value = pair.partition("=")
            if key and key not in query:
                query[key] = value
        return raw_path.rstrip("/") or "/", query

    def _device_path(self, path: str) -> tuple[str, str] | None:
        prefix = f"{API_PREFIX}/devices/"
        if not path.startswith(prefix):
            return None
        remainder = path[len(prefix):]
        parts = remainder.split("/")
        if not parts or not parts[0]:
            return None
        return parts[0], "/".join(parts[1:])

    def _request_id(self, supplied: str | None) -> str:
        if supplied and re.fullmatch(r"[A-Za-z0-9._:-]{1,80}", supplied):
            return supplied
        return str(uuid.uuid4())

    def _now(self) -> datetime:
        value = self._clock()
        return value.astimezone(UTC) if value.tzinfo else value.replace(tzinfo=UTC)

    def _now_iso(self) -> str:
        return self._now().isoformat()

    def _public_id(self, prefix: str) -> str:
        return prefix + secrets.token_urlsafe(16).rstrip("=")

    def _migrate(self) -> None:
        with self._write_lock, self._database:
            self._database.execute(
                "CREATE TABLE IF NOT EXISTS schema_migrations(version INTEGER PRIMARY KEY)"
            )
            current = self._database.execute(
                "SELECT COALESCE(MAX(version), 0) AS version FROM schema_migrations"
            ).fetchone()["version"]
            if current < 1:
                self._database.executescript(
                    """
                    CREATE TABLE users (
                      id TEXT PRIMARY KEY,
                      username TEXT NOT NULL UNIQUE COLLATE NOCASE,
                      password_hash TEXT NOT NULL,
                      created_at TEXT NOT NULL,
                      disabled_at TEXT
                    );
                    CREATE TABLE user_sessions (
                      id TEXT PRIMARY KEY,
                      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                      token_hash TEXT NOT NULL UNIQUE,
                      expires_at TEXT NOT NULL,
                      revoked_at TEXT,
                      created_at TEXT NOT NULL,
                      last_used_at TEXT
                    );
                    CREATE TABLE devices (
                      id TEXT PRIMARY KEY,
                      owner_user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                      name TEXT NOT NULL,
                      firmware_version TEXT,
                      status TEXT NOT NULL DEFAULT 'active'
                        CHECK (status IN ('active', 'revoked', 'disabled')),
                      created_at TEXT NOT NULL,
                      updated_at TEXT,
                      last_contact_at TEXT
                    );
                    CREATE TABLE device_credentials (
                      id TEXT PRIMARY KEY,
                      device_id TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
                      token_hint TEXT NOT NULL UNIQUE,
                      token_hash TEXT NOT NULL UNIQUE,
                      created_at TEXT NOT NULL,
                      rotated_at TEXT,
                      revoked_at TEXT,
                      last_used_at TEXT
                    );
                    CREATE TABLE telemetry_events (
                      id INTEGER PRIMARY KEY AUTOINCREMENT,
                      device_id TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
                      event_id TEXT NOT NULL,
                      sequence INTEGER NOT NULL CHECK (sequence > 0),
                      measured_at TEXT NOT NULL,
                      temperature_c REAL NOT NULL,
                      humidity_percent REAL NOT NULL CHECK (humidity_percent BETWEEN 0 AND 100),
                      vpd_received REAL,
                      vpd_calculated REAL NOT NULL,
                      payload_hash TEXT NOT NULL,
                      received_at TEXT NOT NULL,
                      UNIQUE(device_id, event_id),
                      UNIQUE(device_id, sequence)
                    );
                    CREATE TABLE device_sync_state (
                      device_id TEXT PRIMARY KEY REFERENCES devices(id) ON DELETE CASCADE,
                      accepted_through INTEGER NOT NULL DEFAULT 0 CHECK (accepted_through >= 0),
                      max_sequence INTEGER NOT NULL DEFAULT 0 CHECK (max_sequence >= 0),
                      last_contact_at TEXT,
                      last_error TEXT
                    );
                    CREATE TABLE audit_logs (
                      id INTEGER PRIMARY KEY AUTOINCREMENT,
                      actor_type TEXT NOT NULL,
                      actor_id TEXT,
                      action TEXT NOT NULL,
                      target_id TEXT,
                      request_id TEXT NOT NULL,
                      metadata_json TEXT NOT NULL DEFAULT '{}',
                      created_at TEXT NOT NULL
                    );
                    CREATE TABLE credential_events (
                      id INTEGER PRIMARY KEY AUTOINCREMENT,
                      device_id TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
                      credential_id TEXT,
                      action TEXT NOT NULL,
                      created_at TEXT NOT NULL
                    );
                    INSERT INTO schema_migrations(version) VALUES (1);
                    """
                )
            if current < 2:
                self._database.executescript(
                    """
                    CREATE INDEX IF NOT EXISTS idx_sessions_user_expiry
                      ON user_sessions(user_id, expires_at);
                    CREATE INDEX IF NOT EXISTS idx_devices_owner_status
                      ON devices(owner_user_id, status, created_at);
                    CREATE INDEX IF NOT EXISTS idx_credentials_device_active
                      ON device_credentials(device_id, revoked_at);
                    CREATE INDEX IF NOT EXISTS idx_events_device_sequence
                      ON telemetry_events(device_id, sequence);
                    CREATE INDEX IF NOT EXISTS idx_events_device_measured
                      ON telemetry_events(device_id, measured_at);
                    CREATE INDEX IF NOT EXISTS idx_audit_target_created
                      ON audit_logs(target_id, created_at);
                    INSERT INTO schema_migrations(version) VALUES (2);
                    """
                )
            if current < 3:
                columns = {
                    row["name"]
                    for row in self._database.execute(
                        "PRAGMA table_info(telemetry_events)"
                    ).fetchall()
                }
                if "source" not in columns:
                    self._database.execute(
                        """ALTER TABLE telemetry_events
                           ADD COLUMN source TEXT NOT NULL DEFAULT 'device'
                           CHECK (source IN ('device', 'app-backfill'))"""
                    )
                self._database.execute(
                    """CREATE INDEX IF NOT EXISTS idx_events_device_source_sequence
                       ON telemetry_events(device_id, source, sequence)"""
                )
                self._database.execute(
                    "INSERT OR IGNORE INTO schema_migrations(version) VALUES (3)"
                )
            if current < 4:
                columns = {
                    row["name"]
                    for row in self._database.execute(
                        "PRAGMA table_info(telemetry_events)"
                    ).fetchall()
                }
                if "capabilities_json" not in columns:
                    self._database.execute(
                        "ALTER TABLE telemetry_events ADD COLUMN capabilities_json "
                        "TEXT NOT NULL DEFAULT '{}'"
                    )
                if "measurements_json" not in columns:
                    self._database.execute(
                        "ALTER TABLE telemetry_events ADD COLUMN measurements_json "
                        "TEXT NOT NULL DEFAULT '{}'"
                    )
                self._database.execute(
                    "INSERT OR IGNORE INTO schema_migrations(version) VALUES (4)"
                )
            if current < 5:
                columns = {row["name"] for row in self._database.execute(
                    "PRAGMA table_info(user_sessions)").fetchall()}
                if "scope" not in columns:
                    self._database.execute(
                        "ALTER TABLE user_sessions ADD COLUMN scope TEXT NOT NULL DEFAULT 'full'"
                    )
                self._database.executescript("""
                    CREATE TABLE IF NOT EXISTS business_sync_state (
                      user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
                      published_at TEXT NOT NULL,
                      source_generated_at TEXT NOT NULL,
                      plant_count INTEGER NOT NULL,
                      action_count INTEGER NOT NULL
                    );
                    CREATE TABLE IF NOT EXISTS business_plants (
                      owner_user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                      id TEXT NOT NULL,
                      payload_json TEXT NOT NULL,
                      name TEXT NOT NULL,
                      status TEXT NOT NULL,
                      PRIMARY KEY(owner_user_id, id)
                    );
                    CREATE TABLE IF NOT EXISTS business_actions (
                      owner_user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                      id TEXT NOT NULL,
                      plant_id TEXT NOT NULL,
                      payload_json TEXT NOT NULL,
                      timestamp TEXT NOT NULL,
                      status TEXT NOT NULL,
                      PRIMARY KEY(owner_user_id, id),
                      FOREIGN KEY(owner_user_id, plant_id)
                        REFERENCES business_plants(owner_user_id, id) ON DELETE CASCADE
                    );
                    CREATE INDEX IF NOT EXISTS idx_business_actions_owner_time
                      ON business_actions(owner_user_id, timestamp DESC);
                    CREATE INDEX IF NOT EXISTS idx_business_actions_owner_plant_time
                      ON business_actions(owner_user_id, plant_id, timestamp DESC);
                    INSERT OR IGNORE INTO schema_migrations(version) VALUES (5);
                """)

    def _audit(
        self,
        actor_type: str,
        actor_id: str | None,
        action: str,
        target_id: str | None,
        request_id: str,
        metadata: dict[str, Any] | None = None,
    ) -> None:
        self._database.execute(
            "INSERT INTO audit_logs(actor_type, actor_id, action, target_id, request_id, metadata_json, created_at) "
            "VALUES (?, ?, ?, ?, ?, ?, ?)",
            (
                actor_type,
                actor_id,
                action,
                target_id,
                request_id,
                json.dumps(metadata or {}, sort_keys=True, separators=(",", ":")),
                self._now_iso(),
            ),
        )

    def _safe_audit(
        self,
        actor_type: str,
        actor_id: str | None,
        action: str,
        target_id: str | None,
        request_id: str,
    ) -> None:
        try:
            self._audit(actor_type, actor_id, action, target_id, request_id)
        except sqlite3.Error:
            pass

    def _error_response(self, error: ApiError, request_id: str) -> ApiResponse:
        body: dict[str, Any] = {
            "error": {
                "code": error.code,
                "message": error.message,
                "retryable": error.retryable,
            },
            "requestId": request_id,
        }
        if error.details:
            body["error"]["details"] = error.details
        response_headers = self._security_headers()
        response_headers["X-Request-ID"] = request_id
        return ApiResponse(error.status, body, response_headers)

    def _success_response(self, body: dict[str, Any], request_id: str) -> ApiResponse:
        if "requestId" not in body:
            body = {**body, "requestId": request_id}
        response_headers = self._security_headers()
        response_headers["X-Request-ID"] = request_id
        return ApiResponse(200, body, response_headers)

    def _security_headers(self) -> dict[str, str]:
        return {
            "Content-Type": "application/json; charset=utf-8",
            "Cache-Control": "no-store",
            "X-Content-Type-Options": "nosniff",
            "X-Frame-Options": "DENY",
            "Referrer-Policy": "no-referrer",
            "Content-Security-Policy": "default-src 'none'",
            "X-Robots-Tag": "noindex, nofollow",
            "Strict-Transport-Security": "max-age=31536000; includeSubDomains",
        }


def _finite_number(value: Any, field: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ApiError(422, "invalid_number", f"{field} invalide")
    number = float(value)
    if not math.isfinite(number):
        raise ApiError(422, "invalid_number", f"{field} invalide")
    return number


def _normalize_capabilities(value: Any) -> dict[str, dict[str, Any]]:
    if value is None:
        return {}
    if not isinstance(value, dict) or len(value) > 100:
        raise ApiError(422, "invalid_capabilities", "Capacités invalides")
    result: dict[str, dict[str, Any]] = {}
    allowed = {"type", "label", "unit", "min", "max", "writable"}
    for raw_key, raw_details in value.items():
        if not isinstance(raw_key, str) or not MEASUREMENT_KEY_RE.fullmatch(raw_key):
            raise ApiError(422, "invalid_capability_key", "Clé de capacité invalide")
        if not isinstance(raw_details, dict) or set(raw_details) - allowed:
            raise ApiError(422, "invalid_capability", "Capacité invalide")
        value_type = raw_details.get("type")
        if value_type not in {"number", "boolean", "text"}:
            raise ApiError(422, "invalid_capability_type", "Type de capacité invalide")
        normalized: dict[str, Any] = {"type": value_type}
        for field, maximum in (("label", 120), ("unit", 32)):
            raw_text = raw_details.get(field)
            if raw_text is not None:
                if not isinstance(raw_text, str) or not 0 < len(raw_text.strip()) <= maximum:
                    raise ApiError(422, "invalid_capability", "Capacité invalide")
                normalized[field] = raw_text.strip()
        for field in ("min", "max"):
            raw_number = raw_details.get(field)
            if raw_number is not None:
                normalized[field] = _finite_number(raw_number, f"capabilities.{raw_key}.{field}")
        if (
            normalized.get("min") is not None
            and normalized.get("max") is not None
            and normalized["min"] > normalized["max"]
        ):
            raise ApiError(422, "invalid_capability_range", "Bornes de capacité invalides")
        writable = raw_details.get("writable", False)
        if not isinstance(writable, bool):
            raise ApiError(422, "invalid_capability", "Capacité invalide")
        if writable:
            normalized["writable"] = True
        result[raw_key] = normalized
    return result


def _normalize_measurements(
    value: Any,
    capabilities: dict[str, dict[str, Any]],
) -> dict[str, Any]:
    if value is None:
        return {}
    if not isinstance(value, dict) or len(value) > 100:
        raise ApiError(422, "invalid_measurements", "Mesures génériques invalides")
    result: dict[str, Any] = {}
    for raw_key, raw_value in value.items():
        if not isinstance(raw_key, str) or not MEASUREMENT_KEY_RE.fullmatch(raw_key):
            raise ApiError(422, "invalid_measurement_key", "Clé de mesure invalide")
        unit = quality = None
        measurement = raw_value
        if isinstance(raw_value, dict):
            if set(raw_value) - {"value", "unit", "quality"} or "value" not in raw_value:
                raise ApiError(422, "invalid_measurement", "Mesure générique invalide")
            measurement = raw_value["value"]
            unit = raw_value.get("unit")
            quality = raw_value.get("quality")
        if isinstance(measurement, bool):
            value_type = "boolean"
            normalized_value: Any = measurement
        elif isinstance(measurement, (int, float)):
            value_type = "number"
            normalized_value = _finite_number(measurement, f"measurements.{raw_key}")
            if abs(normalized_value) > 1_000_000_000_000:
                raise ApiError(422, "measurement_out_of_range", "Mesure générique hors limites")
        elif isinstance(measurement, str) and len(measurement) <= 500:
            value_type = "text"
            normalized_value = measurement
        else:
            raise ApiError(422, "invalid_measurement", "Mesure générique invalide")
        declared = capabilities.get(raw_key, {}).get("type")
        if declared is not None and declared != value_type:
            raise ApiError(422, "measurement_type_mismatch", "Type de mesure incohérent")
        details: dict[str, Any] = {"value": normalized_value}
        for field, raw_text in (("unit", unit), ("quality", quality)):
            if raw_text is not None:
                if not isinstance(raw_text, str) or not 0 < len(raw_text.strip()) <= 32:
                    raise ApiError(422, "invalid_measurement", "Mesure générique invalide")
                details[field] = raw_text.strip()
        result[raw_key] = details if len(details) > 1 else normalized_value
    return result


def _json_depth(value: Any, current: int = 0) -> int:
    if isinstance(value, dict):
        children = value.values()
    elif isinstance(value, list):
        children = value
    else:
        return current
    return max((_json_depth(child, current + 1) for child in children), default=current)


def _calculate_vpd(temperature: float, humidity: float) -> float:
    saturation = 0.6108 * math.exp((17.27 * temperature) / (temperature + 237.3))
    return saturation * (1.0 - humidity / 100.0)


def _parse_timestamp(value: Any) -> datetime:
    if isinstance(value, bool):
        raise ApiError(422, "invalid_timestamp", "Horodatage invalide")
    if isinstance(value, (int, float)):
        try:
            if not math.isfinite(float(value)) or int(value) <= 0:
                raise ApiError(422, "invalid_timestamp", "Horodatage invalide")
            seconds = float(value) / 1000 if value > 100_000_000_000 else float(value)
            return datetime.fromtimestamp(seconds, UTC)
        except (OverflowError, OSError, ValueError):
            raise ApiError(422, "invalid_timestamp", "Horodatage invalide")
    if isinstance(value, str) and len(value) <= 80:
        try:
            parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError:
            raise ApiError(422, "invalid_timestamp", "Horodatage invalide")
        return (parsed if parsed.tzinfo else parsed.replace(tzinfo=UTC)).astimezone(UTC)
    raise ApiError(422, "invalid_timestamp", "Horodatage invalide")


def _positive_int_or_zero(value: str | None, field: str) -> int:
    if value is None or value == "":
        return 0
    if not value.isdigit():
        raise ApiError(400, "invalid_query", f"Paramètre {field} invalide")
    return int(value)


def _positive_int_or_default(value: str | None, default: int) -> int:
    if value is None or value == "":
        return default
    if not value.isdigit() or int(value) <= 0:
        raise ApiError(400, "invalid_query", "Paramètre de pagination invalide")
    return int(value)


def _random_token(prefix: str) -> str:
    return prefix + secrets.token_urlsafe(32).rstrip("=")


def _new_device_token() -> tuple[str, str, str]:
    hint = DEVICE_TOKEN_PREFIX + secrets.token_urlsafe(12).rstrip("=")
    secret = secrets.token_urlsafe(32).rstrip("=")
    raw = hint + "." + secret
    return raw, hint, _scrypt_hash(raw)


def _sha256(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def _scrypt_hash(value: str) -> str:
    salt = secrets.token_bytes(16)
    n, r, p = 16_384, 8, 1
    digest = hashlib.scrypt(value.encode("utf-8"), salt=salt, n=n, r=r, p=p, dklen=32)
    return "scrypt$%d$%d$%d$%s$%s" % (
        n,
        r,
        p,
        _b64(salt),
        _b64(digest),
    )


def _scrypt_verify(value: str, encoded: str) -> bool:
    try:
        scheme, n, r, p, salt_raw, digest_raw = encoded.split("$", 5)
        if scheme != "scrypt":
            return False
        salt = _b64decode(salt_raw)
        expected = _b64decode(digest_raw)
        actual = hashlib.scrypt(
            value.encode("utf-8"),
            salt=salt,
            n=int(n),
            r=int(r),
            p=int(p),
            dklen=len(expected),
        )
        return hmac.compare_digest(actual, expected)
    except (ValueError, TypeError):
        return False


def _b64(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).decode("ascii").rstrip("=")


def _b64decode(value: str) -> bytes:
    return base64.urlsafe_b64decode(value + "=" * (-len(value) % 4))


def _bearer(value: str | None, prefix: str) -> str:
    if not value or not value.startswith("Bearer "):
        raise ApiError(401, "unauthorized", "Authentification requise")
    token = value[7:].strip()
    if not token.startswith(prefix) or len(token) > 512 or any(char.isspace() for char in token):
        raise ApiError(401, "unauthorized", "Authentification requise")
    return token


def _encode_cursor(ingestion_id: int) -> str:
    return _b64(f"ing:{ingestion_id}".encode("ascii"))


def _decode_cursor(value: str | None) -> int | None:
    if not value:
        return None
    try:
        decoded = _b64decode(value).decode("ascii")
        if decoded.startswith("ing:") and decoded[4:].isdigit():
            return int(decoded[4:])
        # Les curseurs v1 fondés sur une séquence source sont ambigus après un
        # backfill. Une reprise à zéro redécharge éventuellement des doublons,
        # que l'application sait ignorer, mais ne masque aucune mesure.
        if decoded.startswith("seq:") and decoded[4:].isdigit():
            return 0
        raise ValueError
    except (ValueError, UnicodeDecodeError):
        raise ApiError(400, "invalid_cursor", "Curseur invalide")

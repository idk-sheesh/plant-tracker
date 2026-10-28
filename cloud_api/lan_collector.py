from __future__ import annotations

import argparse
import hashlib
import ipaddress
import json
import math
import os
import re
import stat
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any


IDENTIFIER_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.:-]{0,79}$")
MAX_SOURCE_BYTES = 8 * 1024 * 1024
MAX_SOURCE_READINGS = 10_000
MAX_BATCH_SIZE = 100
MAX_FUTURE_SKEW_SECONDS = 300


class CollectorError(Exception):
    pass


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):  # noqa: ANN001
        raise CollectorError("Redirection HTTP refusée")


def _private_source_url(value: Any) -> str:
    if not isinstance(value, str):
        raise CollectorError("sourceUrl obligatoire")
    parsed = urllib.parse.urlsplit(value.strip())
    if (
        parsed.scheme != "http"
        or parsed.username is not None
        or parsed.password is not None
        or parsed.path not in {"", "/"}
        or parsed.query
        or parsed.fragment
        or not parsed.hostname
    ):
        raise CollectorError("sourceUrl doit être une origine HTTP privée sans identifiants")
    try:
        address = ipaddress.ip_address(parsed.hostname)
    except ValueError as error:
        raise CollectorError("sourceUrl doit utiliser une adresse IP littérale") from error
    if (
        not address.is_private
        or address.is_loopback
        or address.is_multicast
        or address.is_link_local
        or address.is_unspecified
        or address.is_reserved
    ):
        raise CollectorError("sourceUrl doit cibler une adresse LAN privée")
    try:
        port = parsed.port
    except ValueError as error:
        raise CollectorError("Port source invalide") from error
    host = f"[{address}]" if address.version == 6 else str(address)
    return f"http://{host}{f':{port}' if port is not None else ''}"


def _loopback_api_url(value: Any) -> str:
    if not isinstance(value, str):
        raise CollectorError("apiBaseUrl obligatoire")
    parsed = urllib.parse.urlsplit(value.strip())
    if (
        parsed.scheme != "http"
        or parsed.hostname not in {"127.0.0.1", "::1"}
        or parsed.username is not None
        or parsed.password is not None
        or parsed.path not in {"", "/"}
        or parsed.query
        or parsed.fragment
    ):
        raise CollectorError("L'API du collecteur doit être HTTP sur loopback uniquement")
    try:
        port = parsed.port
    except ValueError as error:
        raise CollectorError("Port API invalide") from error
    host = f"[{parsed.hostname}]" if parsed.hostname == "::1" else parsed.hostname
    return f"http://{host}{f':{port}' if port is not None else ''}"


def _read_json_response(response, maximum: int) -> Any:  # noqa: ANN001
    length = response.headers.get("Content-Length")
    if length is not None and int(length) > maximum:
        raise CollectorError("Réponse trop volumineuse")
    chunks: list[bytes] = []
    size = 0
    while True:
        chunk = response.read(min(65_536, maximum + 1 - size))
        if not chunk:
            break
        size += len(chunk)
        if size > maximum:
            raise CollectorError("Réponse trop volumineuse")
        chunks.append(chunk)
    try:
        return json.loads(b"".join(chunks))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise CollectorError("Réponse JSON invalide") from error


def _request_json(
    opener: urllib.request.OpenerDirector,
    request: urllib.request.Request,
    *,
    maximum: int,
    timeout: int,
) -> Any:
    try:
        with opener.open(request, timeout=timeout) as response:
            if response.status != 200:
                raise CollectorError(f"HTTP {response.status}")
            return _read_json_response(response, maximum)
    except urllib.error.HTTPError as error:
        raise CollectorError(f"HTTP {error.code}") from error
    except urllib.error.URLError as error:
        raise CollectorError("Connexion impossible") from error


def _finite(value: Any, field: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise CollectorError(f"{field} invalide")
    result = float(value)
    if not math.isfinite(result):
        raise CollectorError(f"{field} invalide")
    return result


def _load_config(path: Path) -> dict[str, Any]:
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise CollectorError("Configuration illisible") from error
    if not isinstance(raw, dict) or set(raw) - {"apiBaseUrl", "stateFile", "hubStatusFile", "nodes"}:
        raise CollectorError("Configuration invalide")
    api_base = _loopback_api_url(raw.get("apiBaseUrl"))
    state_file = raw.get("stateFile")
    nodes = raw.get("nodes")
    if not isinstance(state_file, str) or not Path(state_file).is_absolute():
        raise CollectorError("stateFile absolu obligatoire")
    hub_status_file = raw.get("hubStatusFile")
    if hub_status_file is not None and (
        not isinstance(hub_status_file, str)
        or not Path(hub_status_file).is_absolute()
        or Path(hub_status_file) == Path(state_file)
    ):
        raise CollectorError("hubStatusFile absolu et distinct obligatoire")
    if not isinstance(nodes, list) or not 1 <= len(nodes) <= 100:
        raise CollectorError("Entre 1 et 100 nœuds sont requis")
    normalized_nodes = []
    names: set[str] = set()
    cloud_ids: set[str] = set()
    for item in nodes:
        allowed = {"name", "sourceUrl", "sourceDeviceId", "cloudDeviceId", "tokenFile"}
        if not isinstance(item, dict) or set(item) != allowed:
            raise CollectorError("Configuration de nœud invalide")
        name = item["name"]
        source_id = item["sourceDeviceId"]
        cloud_id = item["cloudDeviceId"]
        token_file = item["tokenFile"]
        if not all(isinstance(value, str) and IDENTIFIER_RE.fullmatch(value) for value in (name, source_id, cloud_id)):
            raise CollectorError("Identifiant de nœud invalide")
        if name in names or cloud_id in cloud_ids:
            raise CollectorError("Nœud ou appareil cloud dupliqué")
        if not isinstance(token_file, str) or not Path(token_file).is_absolute():
            raise CollectorError("tokenFile absolu obligatoire")
        names.add(name)
        cloud_ids.add(cloud_id)
        normalized_nodes.append(
            {
                **item,
                "sourceUrl": _private_source_url(item["sourceUrl"]),
            }
        )
    return {"apiBaseUrl": api_base, "stateFile": state_file, "hubStatusFile": hub_status_file, "nodes": normalized_nodes}


def _load_state(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {"nodes": {}}
    try:
        state = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise CollectorError("État local illisible") from error
    if not isinstance(state, dict) or not isinstance(state.get("nodes"), dict):
        raise CollectorError("État local invalide")
    return state


def _write_state(path: Path, state: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".new")
    descriptor = os.open(
        temporary,
        os.O_WRONLY | os.O_CREAT | os.O_TRUNC | getattr(os, "O_NOFOLLOW", 0),
        0o600,
    )
    try:
        encoded = (json.dumps(state, sort_keys=True, separators=(",", ":")) + "\n").encode()
        os.write(descriptor, encoded)
        os.fsync(descriptor)
    finally:
        os.close(descriptor)
    os.replace(temporary, path)
    os.chmod(path, 0o600)


def _token(path: str) -> str:
    token_path = Path(path)
    try:
        metadata = token_path.lstat()
        if not stat.S_ISREG(metadata.st_mode) or token_path.is_symlink():
            raise CollectorError("Fichier token non régulier")
        if os.name != "nt":
            unsafe_bits = stat.S_IWGRP | stat.S_IRWXO | stat.S_IXGRP
            if metadata.st_mode & unsafe_bits:
                raise CollectorError("Permissions du token trop ouvertes")
            effective_uid = os.geteuid()
            if metadata.st_uid not in {0, effective_uid}:
                raise CollectorError("Propriétaire du token invalide")
        value = token_path.read_text(encoding="utf-8").strip()
    except OSError as error:
        raise CollectorError("Token appareil illisible") from error
    if not value.startswith("gt_dev_") or not 40 <= len(value) <= 512 or "\n" in value:
        raise CollectorError("Token appareil invalide")
    return value


def _source_events(
    raw: Any,
    *,
    source_id: str,
    cloud_id: str,
    first_sequence: int,
    capabilities: Any,
) -> list[dict[str, Any]]:
    if not isinstance(raw, list) or len(raw) > MAX_SOURCE_READINGS:
        raise CollectorError("Historique source invalide ou trop volumineux")
    events = []
    for offset, item in enumerate(sorted(raw, key=lambda value: value.get("timestamp", 0) if isinstance(value, dict) else 0)):
        if not isinstance(item, dict) or item.get("deviceId") != source_id:
            raise CollectorError("Identité du nœud source incohérente")
        timestamp = item.get("timestamp")
        if isinstance(timestamp, bool) or not isinstance(timestamp, int) or timestamp <= 0:
            raise CollectorError("Horodatage source invalide")
        temperature = _finite(item.get("temperature"), "temperature")
        humidity = _finite(item.get("humidity"), "humidity")
        vpd = _finite(item.get("vpd"), "vpd")
        if not -50 <= temperature <= 80 or not 0 <= humidity <= 100 or not 0 <= vpd <= 10:
            raise CollectorError("Mesure source hors limites")
        digest = hashlib.sha256(
            f"{source_id}|{timestamp}|{temperature}|{humidity}|{vpd}".encode()
        ).hexdigest()[:16]
        measurements = item.get("measurements")
        if measurements is None:
            measurements = {}
            if isinstance(item.get("lightRaw"), (int, float)) and not isinstance(item.get("lightRaw"), bool):
                measurements["light_adc_raw"] = {
                    "value": item["lightRaw"],
                    "unit": "ADC",
                    "quality": "uncalibrated",
                }
            if isinstance(item.get("lightOn"), bool):
                measurements["light_detected"] = item["lightOn"]
        events.append(
            {
                "deviceId": cloud_id,
                "eventId": f"lan.{source_id}.{timestamp}.{digest}",
                "sequence": first_sequence + offset,
                "timestamp": timestamp,
                "temperature": temperature,
                "humidity": humidity,
                "vpd": vpd,
                "capabilities": capabilities or {},
                "measurements": measurements,
            }
        )
    return events


def _isolate_future_events(
    events: list[dict[str, Any]], quarantine_path: Path, *, now: float | None = None,
) -> tuple[list[dict[str, Any]], int]:
    """Preserve invalid clock records without consuming a cloud sequence."""
    now = time.time() if now is None else now
    future = [event for event in events if event["timestamp"] > now + MAX_FUTURE_SKEW_SECONDS]
    if not future:
        return events, 0
    quarantine = {"schemaVersion": 1, "events": {}}
    if quarantine_path.exists():
        try:
            if quarantine_path.stat().st_size > MAX_SOURCE_BYTES:
                raise ValueError("Too large")
            quarantine = json.loads(quarantine_path.read_text(encoding="utf-8"))
            if quarantine.get("schemaVersion") != 1 or not isinstance(quarantine.get("events"), dict):
                raise ValueError("Invalid quarantine")
        except (OSError, ValueError, AttributeError) as error:
            raise CollectorError("Quarantaine des mesures illisible") from error
    changed = False
    for event in future:
        record = {key: value for key, value in event.items() if key != "sequence"}
        key = hashlib.sha256(json.dumps(record, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
        if key not in quarantine["events"]:
            quarantine["events"][key] = {
                "reason": "timestamp_in_future", "observedAt": int(now), "event": record,
            }
            changed = True
    if len(quarantine["events"]) > MAX_SOURCE_READINGS or len(json.dumps(quarantine).encode()) > MAX_SOURCE_BYTES:
        raise CollectorError("Quarantaine des mesures pleine")
    if changed:
        _write_state(quarantine_path, quarantine)
    valid = [event for event in events if event["timestamp"] <= now + MAX_FUTURE_SKEW_SECONDS]
    for offset, event in enumerate(valid):
        event["sequence"] = events[0]["sequence"] + offset
    return valid, len(future)


def _confirm_ack(response: Any, expected: int) -> None:
    if not isinstance(response, dict):
        raise CollectorError("Accusé API invalide")
    rejected = response.get("rejected")
    accepted = response.get("acceptedThrough")
    if rejected != []:
        codes = sorted({item["code"] for item in rejected
                        if isinstance(item, dict) and isinstance(item.get("code"), str)
                        and re.fullmatch(r"[a-z_]{1,64}", item["code"])}) if isinstance(rejected, list) else []
        raise CollectorError("Accusé API incomplet : " + (", ".join(codes[:5]) or "rejets invalides"))
    if isinstance(accepted, bool) or not isinstance(accepted, int) or accepted < expected:
        raise CollectorError(f"Accusé API incomplet : séquence attendue {expected} non confirmée")


def collect(config_path: Path) -> dict[str, Any]:
    config = _load_config(config_path)
    state_path = Path(config["stateFile"])
    state = _load_state(state_path)
    hub_path = Path(config["hubStatusFile"]) if config["hubStatusFile"] else None
    hub_state = _load_hub_state(hub_path) if hub_path else None
    opener = urllib.request.build_opener(_NoRedirect())
    results = []
    failed = False
    for node in config["nodes"]:
        name = node["name"]
        node_state = state["nodes"].setdefault(name, {"lastTimestamp": 0, "nextSequence": 1})
        try:
            status_request = urllib.request.Request(
                node["sourceUrl"] + "/status",
                headers={"Accept": "application/json"},
            )
            status = _request_json(opener, status_request, maximum=64 * 1024, timeout=8)
            if not isinstance(status, dict) or status.get("deviceId") != node["sourceDeviceId"]:
                raise CollectorError("Identité /status incohérente")
            since = int(node_state.get("lastTimestamp", 0))
            readings_url = node["sourceUrl"] + "/readings?" + urllib.parse.urlencode({"since": since})
            readings = _request_json(
                opener,
                urllib.request.Request(readings_url, headers={"Accept": "application/json"}),
                maximum=MAX_SOURCE_BYTES,
                timeout=20,
            )
            events = _source_events(
                readings,
                source_id=node["sourceDeviceId"],
                cloud_id=node["cloudDeviceId"],
                first_sequence=int(node_state.get("nextSequence", 1)),
                capabilities=status.get("capabilities"),
            )
            events, quarantined = _isolate_future_events(
                events, state_path.with_name(state_path.name + ".quarantine.json"),
            )
            accepted = 0
            token = _token(node["tokenFile"])
            for offset in range(0, len(events), MAX_BATCH_SIZE):
                batch = events[offset : offset + MAX_BATCH_SIZE]
                body = json.dumps(
                    {
                        "schemaVersion": 1,
                        "deviceId": node["cloudDeviceId"],
                        "firmwareVersion": status.get("firmwareVersion"),
                        "readings": batch,
                    },
                    separators=(",", ":"),
                ).encode()
                request = urllib.request.Request(
                    f"{config['apiBaseUrl']}/api/v1/devices/{urllib.parse.quote(node['cloudDeviceId'], safe='')}/telemetry",
                    data=body,
                    method="POST",
                    headers={
                        "Accept": "application/json",
                        "Authorization": f"Bearer {token}",
                        "Content-Type": "application/json",
                    },
                )
                response = _request_json(opener, request, maximum=1024 * 1024, timeout=15)
                expected = batch[-1]["sequence"]
                _confirm_ack(response, expected)
                node_state["lastTimestamp"] = batch[-1]["timestamp"]
                node_state["nextSequence"] = expected + 1
                _write_state(state_path, state)
                accepted += len(batch)
            if hub_state is not None:
                previous = hub_state["devices"].get(node["cloudDeviceId"], {})
                latest = events[-1] if events else None
                hub_state["devices"][node["cloudDeviceId"]] = {
                    "name": name,
                    "status": "ok",
                    "checkedAt": int(time.time()),
                    "measuredAt": latest["timestamp"] if latest else previous.get("measuredAt"),
                    "metrics": _hub_metrics(latest) if latest else previous.get("metrics"),
                }
            results.append({"node": name, "status": "ok", "accepted": accepted,
                            "quarantined": quarantined})
        except (CollectorError, OSError, ValueError) as error:
            failed = True
            if hub_state is not None:
                previous = hub_state["devices"].get(node["cloudDeviceId"], {})
                hub_state["devices"][node["cloudDeviceId"]] = {
                    "name": name,
                    "status": "offline",
                    "checkedAt": int(time.time()),
                    "measuredAt": previous.get("measuredAt"),
                    "metrics": previous.get("metrics"),
                }
            results.append({"node": name, "status": "error", "error": str(error)})
    if hub_path is not None:
        hub_state["updatedAt"] = int(time.time())
        _write_state(hub_path, hub_state)
    if failed:
        raise CollectorError(json.dumps({"nodes": results}, ensure_ascii=False))
    return {"nodes": results}


def _load_hub_state(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {"schemaVersion": 1, "updatedAt": None, "devices": {}}
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
        if raw.get("schemaVersion") != 1 or not isinstance(raw.get("devices"), dict):
            raise ValueError("Invalid hub status")
        return raw
    except (OSError, ValueError, AttributeError) as error:
        raise CollectorError("État hub illisible") from error


def _hub_metrics(event: dict[str, Any]) -> dict[str, Any]:
    measurements = event["measurements"]
    raw_light = measurements.get("light_adc_raw")
    if isinstance(raw_light, dict):
        raw_light = raw_light.get("value")
    return {
        "temperature_c": event["temperature"],
        "humidity_percent": event["humidity"],
        "vpd_kpa": event["vpd"],
        "light_raw": raw_light if isinstance(raw_light, (int, float)) and not isinstance(raw_light, bool) and 0 <= raw_light <= 4095 else None,
        "light_on": measurements.get("light_detected") if isinstance(measurements.get("light_detected"), bool) else None,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Collecteur LAN vers l'API GardenJournal")
    parser.add_argument("--config", required=True, type=Path)
    args = parser.parse_args()
    try:
        print(json.dumps(collect(args.config), ensure_ascii=False))
    except CollectorError as error:
        print(f"Collecte échouée: {error}", file=sys.stderr)
        raise SystemExit(1) from error


if __name__ == "__main__":
    main()

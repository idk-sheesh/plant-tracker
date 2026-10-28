"""Voluntary, account-scoped GardenJournal snapshot and read projections.

No local SQLite file, image path, credential or device secret crosses this
contract. The phone publishes a complete snapshot explicitly; readers only see
the last committed snapshot for their own account.
"""

from __future__ import annotations

import json
import math
import sqlite3
from datetime import datetime, timezone
from typing import Any


PLANT_FIELDS = {
    "id", "name", "variety", "groupName", "spaceName", "cultureType",
    "status", "pottingDate", "createdAt", "updatedAt", "lastActivityAt", "notes",
}
ACTION_FIELDS = {
    "id", "plantId", "type", "timestamp", "status", "quantity",
    "quantityUnit", "ph", "tds", "productUsed", "pruningType", "notes",
    "harvestWeightFresh", "harvestWeightStored", "harvestWeightWaste",
}


class BusinessValidationError(ValueError):
    pass


def _timestamp(value: Any, name: str) -> str:
    if not isinstance(value, str) or len(value) > 50:
        raise BusinessValidationError(f"{name} invalide")
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise BusinessValidationError(f"{name} invalide") from exc
    if parsed.tzinfo is None:
        raise BusinessValidationError(f"{name} sans fuseau horaire")
    return parsed.astimezone(timezone.utc).isoformat()


def _optional_text(value: Any, name: str, maximum: int = 1000) -> str | None:
    if value is None:
        return None
    if not isinstance(value, str) or len(value) > maximum or "\x00" in value:
        raise BusinessValidationError(f"{name} invalide")
    return value


def _required_text(value: Any, name: str, maximum: int = 128) -> str:
    result = _optional_text(value, name, maximum)
    if not result or not result.strip():
        raise BusinessValidationError(f"{name} obligatoire")
    return result


def _optional_number(value: Any, name: str) -> float | None:
    if value is None:
        return None
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        raise BusinessValidationError(f"{name} invalide")
    return float(value)


def _plant(raw: Any) -> dict[str, Any]:
    if not isinstance(raw, dict) or set(raw) - PLANT_FIELDS:
        raise BusinessValidationError("Champs plante invalides")
    status = _required_text(raw.get("status"), "Statut", 20)
    if status not in {"active", "harvested", "dead"}:
        raise BusinessValidationError("Statut plante invalide")
    return {
        "id": _required_text(raw.get("id"), "ID plante"),
        "name": _required_text(raw.get("name"), "Nom plante", 200),
        "variety": _optional_text(raw.get("variety"), "Variété", 200),
        "groupName": _optional_text(raw.get("groupName"), "Groupe", 200),
        "spaceName": _optional_text(raw.get("spaceName"), "Espace", 200),
        "cultureType": _optional_text(raw.get("cultureType"), "Culture", 100),
        "status": status,
        "pottingDate": _timestamp(raw.get("pottingDate"), "Date de mise en pot"),
        "createdAt": _timestamp(raw.get("createdAt"), "Création plante"),
        "updatedAt": _timestamp(raw.get("updatedAt"), "Mise à jour plante"),
        "lastActivityAt": _timestamp(raw["lastActivityAt"], "Dernière activité") if raw.get("lastActivityAt") else None,
        "notes": _optional_text(raw.get("notes"), "Notes plante", 4000),
    }


def _action(raw: Any, plant_names: dict[str, str]) -> dict[str, Any]:
    if not isinstance(raw, dict) or set(raw) - ACTION_FIELDS:
        raise BusinessValidationError("Champs action invalides")
    plant_id = _required_text(raw.get("plantId"), "ID plante")
    if plant_id not in plant_names:
        raise BusinessValidationError("Action sans plante dans le snapshot")
    status = _required_text(raw.get("status"), "Statut action", 20)
    if status not in {"planned", "done"}:
        raise BusinessValidationError("Statut action invalide")
    return {
        "id": _required_text(raw.get("id"), "ID action"),
        "plantId": plant_id,
        "plantName": plant_names[plant_id],
        "type": _required_text(raw.get("type"), "Type action", 100),
        "timestamp": _timestamp(raw.get("timestamp"), "Date action"),
        "status": status,
        "quantity": _optional_number(raw.get("quantity"), "Quantité"),
        "quantityUnit": _optional_text(raw.get("quantityUnit"), "Unité", 40),
        "ph": _optional_number(raw.get("ph"), "pH"),
        "tds": _optional_number(raw.get("tds"), "TDS"),
        "productUsed": _optional_text(raw.get("productUsed"), "Produit", 200),
        "pruningType": _optional_text(raw.get("pruningType"), "Taille", 100),
        "notes": _optional_text(raw.get("notes"), "Notes action", 4000),
        "harvestWeightFresh": _optional_number(raw.get("harvestWeightFresh"), "Poids récolté"),
        "harvestWeightStored": _optional_number(raw.get("harvestWeightStored"), "Poids conservé"),
        "harvestWeightWaste": _optional_number(raw.get("harvestWeightWaste"), "Poids écarté"),
    }


def validate_snapshot(payload: dict[str, Any]) -> tuple[str, list[dict[str, Any]], list[dict[str, Any]]]:
    if set(payload) != {"schemaVersion", "generatedAt", "plants", "actions"} or payload["schemaVersion"] != 1:
        raise BusinessValidationError("Schéma snapshot invalide")
    generated_at = _timestamp(payload["generatedAt"], "Date du snapshot")
    plants_raw, actions_raw = payload["plants"], payload["actions"]
    if not isinstance(plants_raw, list) or len(plants_raw) > 2000:
        raise BusinessValidationError("Nombre de plantes invalide")
    if not isinstance(actions_raw, list) or len(actions_raw) > 10000:
        raise BusinessValidationError("Nombre d'actions invalide")
    plants = [_plant(row) for row in plants_raw]
    plant_ids = {row["id"] for row in plants}
    if len(plant_ids) != len(plants):
        raise BusinessValidationError("ID plante dupliqué")
    plant_names = {plant["id"]: plant["name"] for plant in plants}
    actions = [_action(row, plant_names) for row in actions_raw]
    if len({row["id"] for row in actions}) != len(actions):
        raise BusinessValidationError("ID action dupliqué")
    return generated_at, plants, actions


def publish(database: sqlite3.Connection, user_id: str, payload: dict[str, Any], now: str) -> dict[str, Any]:
    generated_at, plants, actions = validate_snapshot(payload)
    previous = database.execute(
        "SELECT source_generated_at FROM business_sync_state WHERE user_id = ?", (user_id,)
    ).fetchone()
    if previous and datetime.fromisoformat(generated_at) < datetime.fromisoformat(previous["source_generated_at"]):
        raise BusinessValidationError("Snapshot plus ancien que la dernière publication")
    database.execute("DELETE FROM business_actions WHERE owner_user_id = ?", (user_id,))
    database.execute("DELETE FROM business_plants WHERE owner_user_id = ?", (user_id,))
    database.executemany(
        "INSERT INTO business_plants(owner_user_id, id, payload_json, name, status) VALUES (?, ?, ?, ?, ?)",
        [(user_id, p["id"], json.dumps(p, ensure_ascii=False), p["name"], p["status"]) for p in plants],
    )
    database.executemany(
        "INSERT INTO business_actions(owner_user_id, id, plant_id, payload_json, timestamp, status) VALUES (?, ?, ?, ?, ?, ?)",
        [(user_id, a["id"], a["plantId"], json.dumps(a, ensure_ascii=False), a["timestamp"], a["status"]) for a in actions],
    )
    database.execute(
        "INSERT INTO business_sync_state(user_id, published_at, source_generated_at, plant_count, action_count) "
        "VALUES (?, ?, ?, ?, ?) ON CONFLICT(user_id) DO UPDATE SET "
        "published_at=excluded.published_at, source_generated_at=excluded.source_generated_at, "
        "plant_count=excluded.plant_count, action_count=excluded.action_count",
        (user_id, now, generated_at, len(plants), len(actions)),
    )
    return {"publishedAt": now, "sourceGeneratedAt": generated_at,
            "plantCount": len(plants), "actionCount": len(actions)}


def sync_status(database: sqlite3.Connection, user_id: str) -> dict[str, Any]:
    row = database.execute(
        "SELECT published_at, source_generated_at, plant_count, action_count "
        "FROM business_sync_state WHERE user_id = ?", (user_id,)
    ).fetchone()
    if row is None:
        return {"source": "phone-local-only", "publishedAt": None,
                "sourceGeneratedAt": None, "plantCount": 0, "actionCount": 0}
    return {"source": "server-snapshot", "publishedAt": row["published_at"],
            "sourceGeneratedAt": row["source_generated_at"],
            "plantCount": row["plant_count"], "actionCount": row["action_count"]}


def _page(query: dict[str, str]) -> tuple[int, int]:
    if set(query) - {"limit", "offset"}:
        raise BusinessValidationError("Paramètre de liste invalide")
    try:
        limit = int(query.get("limit", "100"))
        offset = int(query.get("offset", "0"))
    except ValueError as exc:
        raise BusinessValidationError("Pagination invalide") from exc
    if not 1 <= limit <= 200 or not 0 <= offset <= 100000:
        raise BusinessValidationError("Pagination invalide")
    return limit, offset


def list_plants(database: sqlite3.Connection, user_id: str, query: dict[str, str]) -> dict[str, Any]:
    limit, offset = _page(query)
    total = database.execute(
        "SELECT COUNT(*) FROM business_plants WHERE owner_user_id = ?", (user_id,)
    ).fetchone()[0]
    rows = database.execute(
        "SELECT payload_json FROM business_plants WHERE owner_user_id = ? "
        "ORDER BY CASE status WHEN 'active' THEN 0 ELSE 1 END, name COLLATE NOCASE, id "
        "LIMIT ? OFFSET ?", (user_id, limit, offset)
    ).fetchall()
    return {"plants": [json.loads(row[0]) for row in rows], "total": total,
            "limit": limit, "offset": offset}


def plant_detail(database: sqlite3.Connection, user_id: str, plant_id: str) -> dict[str, Any] | None:
    row = database.execute(
        "SELECT payload_json FROM business_plants WHERE owner_user_id = ? AND id = ?",
        (user_id, plant_id),
    ).fetchone()
    if row is None:
        return None
    actions = database.execute(
        "SELECT payload_json FROM business_actions WHERE owner_user_id = ? AND plant_id = ? "
        "ORDER BY timestamp DESC LIMIT 100", (user_id, plant_id),
    ).fetchall()
    return {"plant": json.loads(row[0]), "actions": [json.loads(a[0]) for a in actions]}


def list_actions(database: sqlite3.Connection, user_id: str, query: dict[str, str]) -> dict[str, Any]:
    if set(query) - {"limit", "offset", "plantId"}:
        raise BusinessValidationError("Paramètre de liste invalide")
    limit, offset = _page({k: v for k, v in query.items() if k != "plantId"})
    plant_id = query.get("plantId")
    if plant_id is not None:
        _required_text(plant_id, "ID plante")
    where = "owner_user_id = ?" + (" AND plant_id = ?" if plant_id else "")
    args: tuple[Any, ...] = (user_id, plant_id) if plant_id else (user_id,)
    total = database.execute(f"SELECT COUNT(*) FROM business_actions WHERE {where}", args).fetchone()[0]
    rows = database.execute(
        f"SELECT payload_json FROM business_actions WHERE {where} "
        "ORDER BY timestamp DESC, id DESC LIMIT ? OFFSET ?", (*args, limit, offset)
    ).fetchall()
    return {"actions": [json.loads(row[0]) for row in rows], "total": total,
            "limit": limit, "offset": offset}


def stats(database: sqlite3.Connection, user_id: str, now: datetime) -> dict[str, Any]:
    plants = [json.loads(row[0]) for row in database.execute(
        "SELECT payload_json FROM business_plants WHERE owner_user_id = ?", (user_id,)
    )]
    active = [p for p in plants if p["status"] == "active"]
    groups: dict[str, int] = {}
    spaces: dict[str, int] = {}
    for plant in active:
        if plant["groupName"]:
            groups[plant["groupName"]] = groups.get(plant["groupName"], 0) + 1
        if plant["spaceName"]:
            spaces[plant["spaceName"]] = spaces.get(plant["spaceName"], 0) + 1
    actions = database.execute(
        "SELECT timestamp, status FROM business_actions WHERE owner_user_id = ?", (user_id,)
    ).fetchall()
    recent = sum(1 for a in actions if a["status"] == "done" and
                 (now - datetime.fromisoformat(a["timestamp"])).total_seconds() <= 7 * 86400 and
                 datetime.fromisoformat(a["timestamp"]) <= now)
    last_activity = max(
        (a["timestamp"] for a in actions if a["status"] == "done"),
        key=datetime.fromisoformat, default=None,
    )
    measurements = database.execute(
        "SELECT COUNT(*) FROM telemetry_events JOIN devices ON devices.id = telemetry_events.device_id "
        "WHERE devices.owner_user_id = ?", (user_id,)
    ).fetchone()[0]
    return {"activePlants": len(active), "plantsByGroup": groups, "plantsBySpace": spaces,
            "recentActions7d": recent, "lastActivityAt": last_activity,
            "measurementCount": measurements}

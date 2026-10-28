from __future__ import annotations

import json
import os
import secrets
import unittest
from pathlib import Path

from cloud_api.admin import reset_user_password, rotate_device_token
from cloud_api.app import CloudService


class LocalAdminTest(unittest.TestCase):
    def test_password_reset_revokes_sessions_and_replaces_password(self) -> None:
        test_root = Path("cloud_api/.test-data").resolve()
        test_root.mkdir(parents=True, exist_ok=True)
        stem = f"password-{secrets.token_hex(8)}"
        database = test_root / f"{stem}.db"
        output = test_root / f"{stem}.password"
        old_password = secrets.token_urlsafe(20) + "Aa1!"
        try:
            service = CloudService(database)
            register = service.handle(
                "POST",
                "/api/v1/auth/register",
                body=json.dumps(
                    {"username": "owner", "password": old_password}
                ).encode(),
            )
            self.assertEqual(register.status, 200)
            login = service.handle(
                "POST",
                "/api/v1/auth/login",
                body=json.dumps(
                    {"username": "owner", "password": old_password}
                ).encode(),
            )
            self.assertEqual(login.status, 200)
            old_session = login.body["sessionToken"]
            service.close()

            reset_user_password(database, "owner", output)
            new_password = output.read_text(encoding="utf-8").strip()
            self.assertGreaterEqual(len(new_password), 20)
            if os.name != "nt":
                self.assertEqual(output.stat().st_mode & 0o777, 0o600)

            service = CloudService(database)
            try:
                devices = service.handle(
                    "GET",
                    "/api/v1/devices",
                    headers={"Authorization": f"Bearer {old_session}"},
                )
                self.assertEqual(devices.status, 401)
                old_login = service.handle(
                    "POST",
                    "/api/v1/auth/login",
                    body=json.dumps(
                        {"username": "owner", "password": old_password}
                    ).encode(),
                )
                self.assertEqual(old_login.status, 401)
                new_login = service.handle(
                    "POST",
                    "/api/v1/auth/login",
                    body=json.dumps(
                        {"username": "owner", "password": new_password}
                    ).encode(),
                )
                self.assertEqual(new_login.status, 200)
            finally:
                service.close()
        finally:
            for suffix in (".db", ".db-shm", ".db-wal", ".password"):
                (test_root / f"{stem}{suffix}").unlink(missing_ok=True)

    def test_rotation_writes_once_and_revokes_previous_token(self) -> None:
        test_root = Path("cloud_api/.test-data").resolve()
        test_root.mkdir(parents=True, exist_ok=True)
        stem = f"admin-{secrets.token_hex(8)}"
        database = test_root / f"{stem}.db"
        output = test_root / f"{stem}.token"
        try:
            service = CloudService(database)
            password = secrets.token_urlsafe(20) + "Aa1!"
            register = service.handle(
                "POST",
                "/api/v1/auth/register",
                body=json.dumps({"username": "owner", "password": password}).encode(),
            )
            self.assertEqual(register.status, 200)
            login = service.handle(
                "POST",
                "/api/v1/auth/login",
                body=json.dumps({"username": "owner", "password": password}).encode(),
            )
            session = login.body["sessionToken"]
            provision = service.handle(
                "POST",
                "/api/v1/devices",
                headers={"Authorization": f"Bearer {session}"},
                body=json.dumps({"name": "Serre"}).encode(),
            )
            device_id = provision.body["device"]["id"]
            old_token = provision.body["deviceToken"]
            service.close()

            rotate_device_token(database, device_id, output)
            new_token = output.read_text(encoding="utf-8").strip()
            self.assertTrue(new_token.startswith("gt_dev_"))
            if os.name != "nt":
                self.assertEqual(output.stat().st_mode & 0o777, 0o600)
            with self.assertRaises(FileExistsError):
                rotate_device_token(database, device_id, output)

            service = CloudService(database)
            try:
                payload = json.dumps(
                    {
                        "deviceId": device_id,
                        "eventId": "evt-1",
                        "sequence": 1,
                        "timestamp": 1_789_400_000,
                        "temperature": 23.0,
                        "humidity": 60.0,
                    }
                ).encode()
                path = f"/api/v1/devices/{device_id}/telemetry"
                self.assertEqual(
                    service.handle(
                        "POST",
                        path,
                        headers={"Authorization": f"Bearer {old_token}"},
                        body=payload,
                    ).status,
                    401,
                )
                self.assertEqual(
                    service.handle(
                        "POST",
                        path,
                        headers={"Authorization": f"Bearer {new_token}"},
                        body=payload,
                    ).status,
                    200,
                )
            finally:
                service.close()
        finally:
            for suffix in (".db", ".db-shm", ".db-wal", ".token"):
                (test_root / f"{stem}{suffix}").unlink(missing_ok=True)


if __name__ == "__main__":
    unittest.main()

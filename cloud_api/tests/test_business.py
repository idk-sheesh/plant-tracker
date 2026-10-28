import json
import unittest
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone

from cloud_api.app import CloudService


class BusinessSnapshotTest(unittest.TestCase):
    def setUp(self):
        self.now = datetime(2026, 9, 20, 12, tzinfo=timezone.utc)
        self.service = CloudService(":memory:", clock=lambda: self.now)
        self.owner = self._register_and_login("owner")
        self.other = self._register_and_login("other")

    def tearDown(self):
        self.service.close()

    def _request(self, method, path, token=None, payload=None):
        return self.service.handle(
            method, path,
            headers={"Authorization": "Bearer " + token} if token else {},
            body=json.dumps(payload).encode() if payload is not None else b"",
            remote_ip="127.0.0.1",
        )

    def _register_and_login(self, username):
        password = "CorrectPassword123!"
        response = self._request("POST", "/api/v1/auth/register",
                                 payload={"username": username, "password": password})
        self.assertEqual(response.status, 200)
        response = self._request("POST", "/api/v1/auth/login",
                                 payload={"username": username, "password": password})
        self.assertEqual(response.status, 200)
        return response.body["sessionToken"]

    def _snapshot(self):
        stamp = self.now.isoformat()
        return {
            "schemaVersion": 1, "generatedAt": stamp,
            "plants": [{"id": "plant-1", "name": "A", "status": "active",
                        "pottingDate": stamp, "createdAt": stamp,
                        "updatedAt": stamp, "groupName": "Groupe A",
                        "spaceName": "Serre"}],
            "actions": [{"id": "action-1", "plantId": "plant-1",
                         "type": "arrosage", "timestamp": stamp,
                         "status": "done", "quantity": 1.5}],
        }

    def test_publication_and_account_isolation(self):
        snapshot = self._snapshot()
        self.assertEqual(self._request("POST", "/api/v1/sync/snapshot", self.owner,
                                       snapshot).status, 200)
        plants = self._request("GET", "/api/v1/plants", self.owner)
        self.assertEqual(plants.body["total"], 1)
        self.assertEqual(plants.body["plants"][0]["spaceName"], "Serre")
        self.assertNotIn("photo_path", json.dumps(plants.body))
        self.assertEqual(self._request("GET", "/api/v1/plants/plant-1", self.owner).status, 200)
        self.assertEqual(self._request("GET", "/api/v1/actions", self.owner).body["total"], 1)
        self.assertEqual(self._request("GET", "/api/v1/stats", self.owner).body["activePlants"], 1)
        self.assertEqual(self._request("GET", "/api/v1/sync/status", self.owner).body["source"],
                         "server-snapshot")
        self.assertEqual(self._request("GET", "/api/v1/plants", self.other).body["total"], 0)
        self.assertEqual(self._request("GET", "/api/v1/plants/plant-1", self.other).status, 404)
        self.assertEqual(self._request("GET", "/api/v1/plants").status, 401)

    def test_read_scope_cannot_write_or_reuse_after_logout(self):
        read = self._request("POST", "/api/v1/auth/login", payload={
            "username": "owner", "password": "CorrectPassword123!",
            "scope": "gardenjournal.read"})
        token = read.body["sessionToken"]
        self.assertEqual(self._request("GET", "/api/v1/me", token).body["scope"],
                         "gardenjournal.read")
        self.assertEqual(self._request("POST", "/api/v1/sync/snapshot", token,
                                       self._snapshot()).status, 403)
        self.assertEqual(self._request("POST", "/api/v1/devices", token,
                                       {"name": "bad"}).status, 403)
        self.assertEqual(self._request("POST", "/api/v1/auth/logout", token).status, 200)
        self.assertEqual(self._request("GET", "/api/v1/plants", token).status, 401)
        self.assertEqual(self._request("GET", "/api/v1/plants", "gt_sess_bad").status, 401)

    def test_invalid_snapshot_keeps_last_good_copy(self):
        original = self._snapshot()
        self.assertEqual(self._request("POST", "/api/v1/sync/snapshot", self.owner,
                                       original).status, 200)
        invalid = self._snapshot()
        invalid["plants"][0]["name"] = "Different"
        invalid["actions"][0]["plantId"] = "another"
        self.assertEqual(self._request("POST", "/api/v1/sync/snapshot", self.owner,
                                       invalid).status, 400)
        self.assertEqual(self._request("GET", "/api/v1/plants/plant-1", self.owner)
                         .body["plant"]["name"], "A")
        invalid = self._snapshot()
        invalid["plants"][0]["password"] = "secret"
        self.assertEqual(self._request("POST", "/api/v1/sync/snapshot", self.owner,
                                       invalid).status, 400)
        self.assertEqual(self._request("GET", "/api/v1/actions?limit=0", self.owner).status, 400)
        self.assertEqual(self._request("GET", "/api/v1/plants/%27OR%271%27", self.owner).status, 404)
        self.assertEqual(self._request("GET", "/api/v1/plants/missing", self.owner).status, 404)

    def test_expired_read_session_and_unpublished_status(self):
        self.assertEqual(self._request("GET", "/api/v1/sync/status", self.owner)
                         .body["source"], "phone-local-only")
        read = self._request("POST", "/api/v1/auth/login", payload={
            "username": "owner", "password": "CorrectPassword123!",
            "scope": "gardenjournal.read"})
        self.now += timedelta(hours=13)
        self.assertEqual(self._request("GET", "/api/v1/stats", read.body["sessionToken"]).status,
                         401)

    def test_parallel_read_session_requests_share_sqlite_safely(self):
        self.assertEqual(self._request("POST", "/api/v1/sync/snapshot", self.owner,
                                       self._snapshot()).status, 200)
        read = self._request("POST", "/api/v1/auth/login", payload={
            "username": "owner", "password": "CorrectPassword123!",
            "scope": "gardenjournal.read"})
        token = read.body["sessionToken"]
        paths = [
            "/api/v1/me",
            "/api/v1/sync/status",
            "/api/v1/plants?limit=100&offset=0",
            "/api/v1/actions?limit=100&offset=0",
            "/api/v1/stats",
            "/api/v1/devices",
        ]

        with ThreadPoolExecutor(max_workers=len(paths)) as pool:
            responses = list(pool.map(
                lambda path: self._request("GET", path, token), paths
            ))

        self.assertTrue(all(response.status == 200 for response in responses))
        self.assertEqual(responses[0].body["username"], "owner")
        self.assertEqual(responses[3].body["total"], 1)


if __name__ == "__main__":
    unittest.main()

from __future__ import annotations

import json
import unittest

from cloud_api.app import CloudService
from cloud_api.server import CloudRequestHandler, create_server


class CloudServerTest(unittest.TestCase):
    def test_server_header_does_not_disclose_python_version(self) -> None:
        handler = object.__new__(CloudRequestHandler)
        self.assertEqual(handler.version_string(), "GardenJournalAPI")

    def test_production_registration_closes_after_first_owner(self) -> None:
        service = CloudService(allow_registration=False)
        self.addCleanup(service.close)

        first = service.handle(
            "POST",
            "/api/v1/auth/register",
            body=json.dumps(
                {"username": "owner", "password": "First-owner-password-Aa1!"}
            ).encode(),
        )
        second = service.handle(
            "POST",
            "/api/v1/auth/register",
            body=json.dumps(
                {"username": "other", "password": "Second-owner-password-Bb2!"}
            ).encode(),
        )

        self.assertEqual(first.status, 200)
        self.assertEqual(second.status, 403)
        self.assertEqual(second.body["error"]["code"], "registration_closed")

    def test_http_is_only_allowed_with_explicit_local_or_proxy_mode(self) -> None:
        service = CloudService()
        self.addCleanup(service.close)

        with self.assertRaises(ValueError):
            create_server(
                service,
                host="127.0.0.1",
                port=0,
                certificate=None,
                private_key=None,
            )

        server = create_server(
            service,
            host="127.0.0.1",
            port=0,
            certificate=None,
            private_key=None,
            behind_tls_proxy=True,
        )
        self.addCleanup(server.server_close)
        self.assertEqual(server.server_address[0], "127.0.0.1")


if __name__ == "__main__":
    unittest.main()

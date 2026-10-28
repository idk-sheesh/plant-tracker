from __future__ import annotations

import shutil
import unittest
import uuid
from pathlib import Path

from camera_gateway.app import CameraGatewayConfig, CameraGatewayService
from camera_gateway.server import create_server


class CameraGatewayServerTest(unittest.TestCase):
    def test_plain_http_requires_an_explicit_development_or_proxy_mode(self) -> None:
        temporary = Path("camera_gateway/.test-data") / uuid.uuid4().hex
        temporary.mkdir(parents=True)
        self.addCleanup(shutil.rmtree, temporary, True)
        service = CameraGatewayService(
            CameraGatewayConfig(
                camera_id="cam-01",
                camera_name="Caméra",
                zone_id="zone-main",
                device_token="device_" + "a" * 40,
                app_token="app_" + "b" * 40,
            ),
            Path(temporary) / "camera.db",
            Path(temporary) / "photos",
        )
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
            allow_http_for_local_dev=True,
        )
        self.addCleanup(server.server_close)
        self.assertEqual(server.server_address[0], "127.0.0.1")


if __name__ == "__main__":
    unittest.main()

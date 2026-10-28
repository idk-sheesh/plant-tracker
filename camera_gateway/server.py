from __future__ import annotations

import argparse
import json
import os
import ssl
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from .app import CameraGatewayConfig, CameraGatewayService, GatewayResponse
from .telegram import TelegramBotRunner, TelegramClient


class CameraGatewayRequestHandler(BaseHTTPRequestHandler):
    server_version = "GardenJournalCameraGateway"

    def _service(self) -> CameraGatewayService:
        return self.server.camera_service  # type: ignore[attr-defined]

    def _handle(self) -> None:
        content_length_raw = self.headers.get("Content-Length", "0")
        try:
            content_length = int(content_length_raw)
        except ValueError:
            self._send(
                GatewayResponse(
                    400,
                    {"error": {"code": "invalid_length", "message": "Longueur invalide"}},
                    {"Content-Type": "application/json; charset=utf-8"},
                )
            )
            return
        if content_length < 0 or content_length > self._service().max_body_bytes:
            self._send(
                GatewayResponse(
                    413,
                    {"error": {"code": "payload_too_large", "message": "Requête trop volumineuse"}},
                    {"Content-Type": "application/json; charset=utf-8"},
                )
            )
            return
        body = self.rfile.read(content_length) if content_length else b""
        response = self._service().handle(
            self.command,
            self.path,
            headers={key: value for key, value in self.headers.items()},
            body=body,
            remote_ip=self.client_address[0],
        )
        self._send(response)

    def _send(self, response: GatewayResponse) -> None:
        encoded = (
            response.body
            if isinstance(response.body, bytes)
            else json.dumps(
                response.body,
                ensure_ascii=False,
                separators=(",", ":"),
            ).encode("utf-8")
        )
        self.send_response(response.status)
        for key, value in response.headers.items():
            self.send_header(key, value)
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(encoded)

    def do_GET(self) -> None:  # noqa: N802
        self._handle()

    def do_POST(self) -> None:  # noqa: N802
        self._handle()

    def do_OPTIONS(self) -> None:  # noqa: N802
        self._handle()

    def log_message(self, format: str, *args: object) -> None:
        # Ne jamais journaliser les URL, en-têtes ou paramètres bruts.
        return


def create_server(
    service: CameraGatewayService,
    *,
    host: str,
    port: int,
    certificate: str | Path | None,
    private_key: str | Path | None,
    allow_http_for_local_dev: bool = False,
    behind_tls_proxy: bool = False,
) -> ThreadingHTTPServer:
    if certificate is None and private_key is not None or certificate is not None and private_key is None:
        raise ValueError("Le certificat et la clé privée sont obligatoires ensemble")
    if certificate is None and not (allow_http_for_local_dev or behind_tls_proxy):
        raise ValueError("HTTPS obligatoire : certificat et clé privée requis")
    httpd = ThreadingHTTPServer((host, port), CameraGatewayRequestHandler)
    httpd.camera_service = service  # type: ignore[attr-defined]
    if certificate is not None and private_key is not None:
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.minimum_version = ssl.TLSVersion.TLSv1_2
        context.load_cert_chain(str(certificate), str(private_key))
        httpd.socket = context.wrap_socket(httpd.socket, server_side=True)
    return httpd


def _required_environment(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value or value.startswith("<"):
        raise ValueError(f"Variable {name} absente")
    return value


def main() -> None:
    parser = argparse.ArgumentParser(description="Passerelle locale GardenJournal ESP32-CAM")
    parser.add_argument("--host", default=os.environ.get("CAMERA_GATEWAY_HOST", "127.0.0.1"))
    parser.add_argument(
        "--port",
        type=int,
        default=int(os.environ.get("CAMERA_GATEWAY_PORT", "8443")),
    )
    parser.add_argument(
        "--database",
        default=os.environ.get("CAMERA_GATEWAY_DATABASE", "camera_gateway/data/camera.db"),
    )
    parser.add_argument(
        "--photos",
        default=os.environ.get("CAMERA_GATEWAY_PHOTOS", "camera_gateway/data/photos"),
    )
    parser.add_argument("--certificate", default=os.environ.get("CAMERA_GATEWAY_TLS_CERT"))
    parser.add_argument("--private-key", default=os.environ.get("CAMERA_GATEWAY_TLS_KEY"))
    parser.add_argument("--allow-http-for-local-dev", action="store_true")
    parser.add_argument("--behind-tls-proxy", action="store_true")
    parser.add_argument("--backup", help="Crée une sauvegarde SQLite puis quitte")
    args = parser.parse_args()

    config = CameraGatewayConfig(
        camera_id=os.environ.get("CAMERA_ID", "cam-01").strip(),
        camera_name=os.environ.get("CAMERA_NAME", "Caméra principale").strip(),
        zone_id=os.environ.get("CAMERA_ZONE_ID", "zone-main").strip(),
        device_token=_required_environment("CAMERA_DEVICE_TOKEN"),
        app_token=_required_environment("CAMERA_APP_TOKEN"),
    )
    database = Path(args.database)
    database.parent.mkdir(parents=True, exist_ok=True)
    service = CameraGatewayService(config, database, args.photos)
    if args.backup:
        service.backup(args.backup)
        service.close()
        return

    telegram_token = os.environ.get("TELEGRAM_BOT_TOKEN", "").strip()
    telegram_chat_id = os.environ.get("TELEGRAM_CHAT_ID", "").strip()
    if bool(telegram_token) != bool(telegram_chat_id):
        service.close()
        raise ValueError("TELEGRAM_BOT_TOKEN et TELEGRAM_CHAT_ID sont requis ensemble")
    telegram = None
    if telegram_token:
        telegram = TelegramBotRunner(
            service,
            TelegramClient(telegram_token),
            telegram_chat_id,
        )
        telegram.start()

    server = create_server(
        service,
        host=args.host,
        port=args.port,
        certificate=args.certificate,
        private_key=args.private_key,
        allow_http_for_local_dev=args.allow_http_for_local_dev,
        behind_tls_proxy=args.behind_tls_proxy,
    )
    try:
        print("GardenJournal camera gateway listening")
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
        if telegram is not None:
            telegram.stop()
        service.close()


if __name__ == "__main__":
    main()

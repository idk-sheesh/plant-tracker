from __future__ import annotations

import argparse
import json
import os
import ssl
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from .app import CloudService


class CloudRequestHandler(BaseHTTPRequestHandler):
    server_version = "GardenJournalAPI"

    def version_string(self) -> str:
        return self.server_version

    def _service(self) -> CloudService:
        return self.server.cloud_service  # type: ignore[attr-defined]

    def _handle(self) -> None:
        if self.command == "GET" and self.path.split("?", 1)[0] == "/robots.txt":
            self._send_bytes(
                200,
                b"User-agent: *\nDisallow: /\n",
                {
                    "Content-Type": "text/plain; charset=utf-8",
                    "Cache-Control": "no-store",
                    "X-Robots-Tag": "noindex, nofollow",
                    "X-Content-Type-Options": "nosniff",
                },
            )
            return
        content_length_raw = self.headers.get("Content-Length", "0")
        try:
            content_length = int(content_length_raw)
        except ValueError:
            self._send(400, {"error": {"code": "invalid_length", "message": "Longueur invalide"}})
            return
        if content_length < 0 or content_length > self._service().max_body_bytes:
            self._send(413, {"error": {"code": "payload_too_large", "message": "Requête trop volumineuse"}})
            return
        body = self.rfile.read(content_length) if content_length else b""
        response = self._service().handle(
            self.command,
            self.path,
            headers={key: value for key, value in self.headers.items()},
            body=body,
            remote_ip=self.client_address[0],
        )
        self._send(response.status, response.body, response.headers)

    def _send_bytes(
        self,
        status: int,
        body: bytes,
        headers: dict[str, str] | None = None,
    ) -> None:
        self.send_response(status)
        for key, value in (headers or {}).items():
            self.send_header(key, value)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def _send(
        self,
        status: int,
        body: dict[str, object],
        headers: dict[str, str] | None = None,
    ) -> None:
        encoded = json.dumps(body, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        self.send_response(status)
        for key, value in (headers or {}).items():
            self.send_header(key, value)
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(encoded)

    def do_GET(self) -> None:  # noqa: N802
        self._handle()

    def do_POST(self) -> None:  # noqa: N802
        self._handle()

    def do_DELETE(self) -> None:  # noqa: N802
        self._handle()

    def do_OPTIONS(self) -> None:  # noqa: N802
        self._handle()

    def log_message(self, format: str, *args: object) -> None:
        # Do not use BaseHTTPRequestHandler's raw request logging: URLs and
        # future query parameters must never become an accidental log channel.
        return


def create_server(
    service: CloudService,
    *,
    host: str,
    port: int,
    certificate: str | Path | None,
    private_key: str | Path | None,
    allow_http_for_local_dev: bool = False,
    behind_tls_proxy: bool = False,
) -> ThreadingHTTPServer:
    if (certificate is None) != (private_key is None):
        raise ValueError("Le certificat et la clé privée sont obligatoires ensemble")
    if certificate is None and not (allow_http_for_local_dev or behind_tls_proxy):
        raise ValueError("HTTPS obligatoire : certificat et clé privée requis")
    httpd = ThreadingHTTPServer((host, port), CloudRequestHandler)
    httpd.cloud_service = service  # type: ignore[attr-defined]
    if certificate is not None and private_key is not None:
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.minimum_version = ssl.TLSVersion.TLSv1_2
        context.load_cert_chain(str(certificate), str(private_key))
        httpd.socket = context.wrap_socket(httpd.socket, server_side=True)
    return httpd


def main() -> None:
    parser = argparse.ArgumentParser(description="GardenJournal secure cloud API")
    parser.add_argument("--host", default=os.environ.get("CLOUD_HOST", "127.0.0.1"))
    parser.add_argument("--port", type=int, default=int(os.environ.get("CLOUD_PORT", "8443")))
    parser.add_argument("--database", default=os.environ.get("CLOUD_DATABASE", "cloud_api/data/gardenjournal-cloud.db"))
    parser.add_argument("--certificate", default=os.environ.get("CLOUD_TLS_CERT"))
    parser.add_argument("--private-key", default=os.environ.get("CLOUD_TLS_KEY"))
    parser.add_argument(
        "--allow-http-for-local-dev",
        action="store_true",
        help="Autorise HTTP uniquement pour un test local explicite; jamais pour production",
    )
    parser.add_argument(
        "--behind-tls-proxy",
        action="store_true",
        help="Autorise HTTP interne uniquement derrière un proxy/tunnel TLS de confiance",
    )
    parser.add_argument(
        "--allow-registration",
        action="store_true",
        help="Autorise plusieurs inscriptions; sinon seul le premier propriétaire peut être créé",
    )
    parser.add_argument("--backup", help="Crée une sauvegarde SQLite puis quitte")
    args = parser.parse_args()

    database = Path(args.database)
    database.parent.mkdir(parents=True, exist_ok=True)
    service = CloudService(database, allow_registration=args.allow_registration)
    if args.backup:
        service.backup(args.backup)
        service.close()
        return
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
        print("GardenJournal cloud API listening")
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
        service.close()


if __name__ == "__main__":
    main()

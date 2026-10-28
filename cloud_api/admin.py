from __future__ import annotations

import argparse
import os
from pathlib import Path

from .app import CloudService


def _reserve_secret_file(path: Path) -> int:
    path.parent.mkdir(parents=True, exist_ok=True)
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    flags |= getattr(os, "O_NOFOLLOW", 0)
    return os.open(path, flags, 0o600)


def rotate_device_token(database: Path, device_id: str, output: Path) -> None:
    descriptor = _reserve_secret_file(output)
    service: CloudService | None = None
    try:
        service = CloudService(database)
        token = service.rotate_device_token_for_local_admin(device_id)
        encoded = (token + "\n").encode("utf-8")
        os.write(descriptor, encoded)
        os.fsync(descriptor)
    except Exception:
        os.close(descriptor)
        descriptor = -1
        output.unlink(missing_ok=True)
        raise
    finally:
        if descriptor >= 0:
            os.close(descriptor)
        if service is not None:
            service.close()


def reset_user_password(database: Path, username: str, output: Path) -> None:
    descriptor = _reserve_secret_file(output)
    service: CloudService | None = None
    try:
        service = CloudService(database)
        password = service.reset_user_password_for_local_admin(username)
        os.write(descriptor, (password + "\n").encode("utf-8"))
        os.fsync(descriptor)
    except Exception:
        os.close(descriptor)
        descriptor = -1
        output.unlink(missing_ok=True)
        raise
    finally:
        if descriptor >= 0:
            os.close(descriptor)
        if service is not None:
            service.close()


def main() -> None:
    parser = argparse.ArgumentParser(description="Maintenance locale de l'API GardenJournal")
    subparsers = parser.add_subparsers(dest="command", required=True)
    rotate = subparsers.add_parser(
        "rotate-device-token",
        help="Renouvelle un token et l'écrit une seule fois dans un fichier 0600",
    )
    rotate.add_argument("--database", required=True, type=Path)
    rotate.add_argument("--device-id", required=True)
    rotate.add_argument("--output", required=True, type=Path)
    reset = subparsers.add_parser(
        "reset-user-password",
        help="Génère un mot de passe, révoque les sessions et l'écrit dans un fichier 0600",
    )
    reset.add_argument("--database", required=True, type=Path)
    reset.add_argument("--username", required=True)
    reset.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    if args.command == "rotate-device-token":
        rotate_device_token(args.database, args.device_id, args.output)
        print(f"Token renouvelé et écrit dans {args.output}")
    if args.command == "reset-user-password":
        reset_user_password(args.database, args.username, args.output)
        print(f"Mot de passe renouvelé et écrit dans {args.output}")


if __name__ == "__main__":
    main()

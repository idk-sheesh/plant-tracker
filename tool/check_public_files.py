"""Check tracked publication sources without printing matched secret values."""

from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
BLOCKED_SUFFIXES = {".h", ".hpp", ".jks", ".keystore", ".pem", ".key", ".db", ".sqlite", ".sqlite3", ".apk", ".aab"}
SECRET = re.compile(
    r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|"
    r"\bgh[pousr]_[A-Za-z0-9]{20,}|\bgithub_pat_[A-Za-z0-9_]{20,}|"
    r"\bAKIA[A-Z0-9]{16}|\b\d{8,12}:[A-Za-z0-9_-]{30,}"
)
APPROVED_BINARIES = {
    "android/gradle/wrapper/gradle-wrapper.jar",
    "assets/fonts/Roboto-Regular.ttf",
    "assets/fonts/Roboto-Italic.ttf",
    "assets/fonts/Roboto-Bold.ttf",
    "assets/fonts/Roboto-BoldItalic.ttf",
    *{f"docs/preview/{screen}.png" for screen in ("home", "tasks", "observations", "settings")},
}


def main() -> int:
    paths = subprocess.run(
        ["git", "ls-files", "-z"], cwd=ROOT, capture_output=True, check=True
    ).stdout.decode("utf-8").split("\0")
    errors = []
    for name in filter(None, paths):
        path = ROOT / name
        if not path.is_file():
            continue
        if path.is_symlink() or not path.resolve().is_relative_to(ROOT):
            errors.append((name, "external link"))
            continue
        if (path.suffix.lower() in BLOCKED_SUFFIXES
                or path.name.startswith(".env")
                or path.name in {"key.properties", "local.properties"}):
            errors.append((name, "local configuration or private data file"))
            continue
        if path.suffix in {".ttf", ".jar", ".png"}:
            if name not in APPROVED_BINARIES:
                errors.append((name, "unapproved binary or image"))
            continue
        try:
            text = path.read_text(encoding="utf-8-sig")
        except UnicodeDecodeError:
            errors.append((name, "unexpected binary file"))
            continue
        if SECRET.search(text):
            errors.append((name, "credential pattern"))
    for name, reason in errors:
        print(f"Blocked: {name} ({reason})", file=sys.stderr)
    print(f"Source check: {len(errors)} blocked file(s).")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())

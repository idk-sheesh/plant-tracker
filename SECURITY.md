# Configuration and privacy

The local plant journal does not require a hosted service or network credentials.
Optional services must be configured with independently generated credentials.

Only `.template.txt` and signing property templates belong in source control.
Create `.env.cloud`, `.env.camera`, firmware configuration headers and
`android/key.properties` locally. All `.h` and `.hpp` files are ignored by Git.

Run `python tool/check_public_files.py` before pushing. The same check runs in CI.
It rejects tracked firmware headers, environment files, private keys, local
databases and application packages, and checks common credential formats.
Automated checks complement review of the staged changes.

Screenshots in `docs/preview/` are produced by
`test/preview/public_screens_test.dart` from fictional records. They contain no
user photos or live sensor measurements.

Do not include credentials, personal records or backups in issue reports.

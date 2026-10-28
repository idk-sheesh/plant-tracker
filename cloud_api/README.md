# Python API and Raspberry Pi backend

This custom HTTP API was developed for the mobile application, deployed on a
Raspberry Pi and used with ESP32 measurements. The application/backend
integration is functional in the project's private setup.

## Implemented features

- Account authentication and expiring user sessions.
- Separate device credentials, with rotation and revocation.
- Authenticated ingestion of temperature, humidity and other sensor measurements.
- Measurement history, incremental synchronisation and controlled historical backfill.
- Account-scoped, read-only views of plant records, care actions and journal statistics.
- A local ESP32 collector with persistent progress, retries and invalid-record handling.
- SQLite persistence, validation and bounded request processing.

## Data flow

```text
ESP32 -> local collector -> authenticated Python API -> Flutter measurement history
Flutter local journal -> voluntary snapshot -> read-only API views
```

The mobile SQLite database remains the source of truth for manual care records.
Network failures preserve local application data. The API stores its own
server-side database and scopes access to the authenticated account.

## Source layout

| File | Responsibility |
| --- | --- |
| `app.py` | Authentication, devices, telemetry and persistence |
| `business.py` | Journal snapshots and read-only projections |
| `server.py` | HTTP transport and TLS/proxy configuration |
| `lan_collector.py` | Incremental collection from local ESP32 nodes |
| `admin.py` | Local administrative operations |
| `tests/` | API, permissions, transport, collector and calculation tests |

The implementation uses the Python standard library and SQLite. Docker Compose
configuration is available in the repository root. Deployment settings come
from [the text template](../config/cloud.env.template.txt), with credentials
provided locally.

## Verification

From the repository root, using Python 3.11 or newer:

```sh
python -m unittest discover -s cloud_api/tests
```

Tests use temporary databases and simulated HTTP exchanges. They cover account
boundaries, token handling, ingestion validation, duplicate/replayed data,
journal access and collector failure paths.

The operational deployment and the automated tests are separate evidence:
the API has been used in the private setup, while this repository supplies
repeatable software checks. Radio/PCB behaviour and signed firmware rollout
require their own hardware validation.

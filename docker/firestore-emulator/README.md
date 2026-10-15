# Firestore Emulator

Runs the [Cloud Firestore emulator](https://firebase.google.com/docs/emulator-suite/connect_firestore)
and the Emulator UI with the Firebase CLI, so the backend can develop and test against
Firestore without a GCP project or credentials.

It is started by the root `docker-compose.yml` as the `firestore` service:

| Port | Purpose |
| :--- | :--- |
| `8080` | Firestore API (`FIRESTORE_EMULATOR_HOST=localhost:8080` from the host, `firestore:8080` inside compose) |
| `4000` | Emulator UI, browse data at <http://localhost:4000/firestore> |
| `9150` | Firestore websocket used by the Emulator UI |

The emulator uses the project ID `demo-is-it-open` (`FIRESTORE_PROJECT_ID`). The `demo-`
prefix tells Firebase tooling it is offline-only and never talks to a real project.

## Persistence

Data lives in the `firestore_data` volume. On start the emulator imports the last export
from `/data/export`, and on `docker compose stop`/`restart`/`down` it exports back to it. Data written before
an unclean shutdown (e.g. `docker kill`) is lost.

To wipe local data:

```bash
make firestore-reset   # docker compose down -v
```

## Tests

Backend tests run against the same emulator under a separate project ID
(`demo-is-it-open-test`) and clear only that project between tests, so they never touch
your local development data.

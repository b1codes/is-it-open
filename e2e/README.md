# E2E tests

The real Flutter app, driven through its UI, against the real backend. Only the services the app doesn't own are stubbed. The journeys live in `frontend/integration_test/`; this directory holds the stack they run against.

## Quick start

```sh
make e2e-up      # build and start the stack (an empty emulator, then seeded), wait until healthy
make test-e2e    # run the journeys in headless Chrome
make e2e-down
```

`make test-e2e` needs Chrome and a matching chromedriver, on your `PATH` or at `CHROMEDRIVER=/path/to/chromedriver`. `npx @puppeteer/browsers install chromedriver@<your Chrome version>` downloads one. Other options for `e2e/run-web.sh`:

- `E2E_BROWSER_SIZE=390x844` runs the phone layout. The default, `1600x1024`, is the desktop layout with the side menu.
- Arguments are passed to `flutter drive`. For example, `e2e/run-web.sh --no-headless` opens a browser window you can watch.

A failing journey saves a screenshot to `frontend/build/e2e-screenshots/`.

## The stack

`docker-compose.e2e.yml` is its own compose project (`is-it-open-e2e`), so it runs alongside `make up` and never touches dev data.

| Service | Host port | What it is |
| --- | --- | --- |
| `backend` | 18000 | The production image, running the Dockerfile's gunicorn command. Settings are in `e2e/backend.env`. |
| `seed` | — | Runs `manage.py seed_e2e` once before the backend starts |
| `firestore` | — | The emulator, without the dev import/export, so every start is empty |
| `stub` | 18090 | `e2e/stub/server.py`, standing in for every external service (below) |

- **Seed data** (`backend/apps/users/management/commands/seed_e2e.py`): the account `e2e-seeded` / `e2e-password`, with a home in Springfield, IL and two bookmarks: Joe's Pizza (pinned) and Riverside Community Garden, a custom place that only local search finds. The command refuses to run without `FIRESTORE_EMULATOR_HOST`, so the known login can't reach a real project.
- **Stub:**
  - **TomTom** (the backend's `TOMTOM_BASE_URL` points here): search, nearby, place by ID, and geocode, served from the recorded contract fixtures in `contracts/tomtom/fixtures` with dates moved to today. It adds two places whose status doesn't depend on the clock: *All Day Diner* (open 24 hours) and *Night Owl Bakery* (open only 03:00–03:01, so closed). A query or address containing `outage` gets a 503. Every address geocodes to 39.80178, -89.64352.
  - **An iCal feed** at `/calendar/e2e.ics`, with one event a day from yesterday to tomorrow.
  - **Blank map tiles**, so the app never loads OpenStreetMap or Carto (`envs/e2e.json` points the map here).
- **Auth:** journeys sign in with a username and password, the app's own token path. Auth0 isn't used: `AUTH0_MOCK` is off and Auth0 tokens are checked against a domain that doesn't resolve, so all of them are rejected. Never turn `AUTH0_MOCK` on outside a throwaway stack.
- **The app:** `--dart-define=ENV=e2e` loads `frontend/envs/e2e.json`. It points the API at `127.0.0.1:18000` and the map tiles at the stub, and raises the API receive timeout from 3 to 20 seconds, because CI runners and the emulator are slower than production.

### Without Docker

`e2e/start-native.sh` runs the same stack directly on the machine. The iOS job uses it, because GitHub's macOS runners have no Docker. It needs uv, Node.js, Java 21+ and python3. Stop it with `e2e/start-native.sh stop`. Two differences from the Docker stack:

- The emulator listens on port 18080.
- The backend reaches the stub at 127.0.0.1, so pass `--dart-define=E2E_STUB_URL=http://127.0.0.1:18090` to the journeys.

## The journeys (`frontend/integration_test/`)

`app_test.dart` is the one entry point, so the app is built once per run. Each journey starts signed out, with nothing stored on the device. Accounts are created through the API with unique names, so journeys don't depend on each other or on the order they run in.

| File | Covers |
| --- | --- |
| `auth_journey.dart` | Register → log out → log in → relaunch restores the session; the seeded account's places; a wrong password |
| `profile_journey.dart` | A home address is saved, geocoded by the backend, and the map recentres on it; the edit survives a relaunch |
| `places_journey.dart` | Search with Open/Closed status and local results; a bookmark through visit length, My Places, pin, want-to-visit, and removal; quick add, then relabel |
| `settings_journey.dart` | The theme and the 24-hour clock survive a restart (desktop layout only, #43) |
| `calendar_journey.dart` | A saved iCal subscription syncs through `/calendar/proxy` and its events show (#44: the app can't add one yet) |
| `errors_journey.dart` | Backend down (signing in, and a cached session); a TomTom outage; a revoked session |

Helpers (`helpers/e2e.dart`):

- `journey()`: a `testWidgets` that screenshots failures.
- `initApp`: what `main()` does, plus one request that warms up a cold backend.
- `launchApp` / `relaunchApp`.
- `waitFor`: the backend is real, so wait for what you expect. `pumpAndSettle` can return before a response arrives.
- `tapAndSettle`: waits out route transitions and scrolls lazy lists first.
- `typeInto`, `signIn`, `logOut`.
- `openTab`: in the phone layout, it also drags the tab's sheet fully open.
- `BackendApi`, to create accounts and check what the backend stored.
- `eventually`.

**Writing a journey:**

- Check the outcome on the backend (`BackendApi`), not only on screen.
- Find widgets by what the user sees: text, labels, and widget types the screen owns.
- Make it pass in both layouts, including a short phone (`E2E_BROWSER_SIZE=360x640`). Where a layout can't reach a feature, skip with a reason that links an issue.

## Where it runs

| Workflow | When | Runs |
| --- | --- | --- |
| `ci.yml`, `E2E (desktop)` and `E2E (phone)` | Every PR that changes the backend, frontend or E2E files. Part of the required `ci` check | Headless Chrome on Linux, against the compose stack |
| `nightly.yml` → `e2e-mobile.yml` | Nightly, or manually | An iOS simulator (macOS, Docker-free stack, Xcode 16; see #45) and an Android emulator (Linux with KVM, compose stack, through `adb reverse`) |

On failure, the web jobs upload the screenshots, chromedriver's log and the stack's logs. The mobile jobs upload the stack's logs.

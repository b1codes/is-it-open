# E2E tests

The real Flutter app, driven through its UI, against the real backend. Only the services the app doesn't own are stubbed. The journeys live in `frontend/integration_test/`; this directory holds the stack they run against.

## Quick start

```sh
make e2e         # all in one, as CI does: start the stack, run both layouts, tear it down

make e2e-up      # or step by step: build and start the stack (empty emulator, then seeded)
make test-e2e    # the journeys in headless Chrome, desktop layout
make test-e2e-phone  #   ...and in the phone layout (390x844)
make e2e-down
```

| Target | What it does |
| --- | --- |
| `make e2e` | `e2e-up`, both layouts, then `e2e-down`, also when a journey fails |
| `make e2e-up` / `make e2e-down` | Start the stack from scratch and wait until it's healthy / stop it and drop its data |
| `make e2e-logs` | Follow the stack's logs |
| `make e2e-seed` | Reset the seeded account on a running stack, e.g. after trying things by hand |
| `make test-e2e` / `make test-e2e-phone` | The journeys against a running stack. `ARGS=` passes flags to `flutter drive`; `ARGS=--no-headless` opens a browser window you can watch |
| `make e2e-native-up` / `make e2e-native-down` | The stack without Docker (see below) |

The journeys need Chrome. `e2e/run-web.sh` (behind the test targets) uses `CHROMEDRIVER=/path/to/chromedriver` if you set it. Otherwise it uses a `chromedriver` on your `PATH` if it matches your Chrome, or downloads one that does into `frontend/build/chromedriver` (with `npx`). Chrome updates itself, so a chromedriver fetched once goes stale. `E2E_BROWSER_SIZE=WIDTHxHEIGHT` sets any other screen size.

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
  - **An iCal feed** at `/calendar/e2e.ics`, with one event a day from yesterday to tomorrow. The backend's calendar proxy only fetches from public addresses, so the stack lets it reach the stub's host with `SAFE_FETCH_PRIVATE_HOSTS` (`stub`, or `127.0.0.1` without Docker).
  - **Blank map tiles**, so the app never loads OpenStreetMap or Carto (`envs/e2e.json` points the map here).
- **Auth:** journeys sign in with a username and password, the app's own token path. Auth0 isn't used: `AUTH0_MOCK` is off and `AUTH0_DOMAIN` is empty, so every Auth0 token is rejected with a 401, without a JWKS lookup. The backend refuses to start with `AUTH0_MOCK` on and `DEBUG` off.
- **The app:** `--dart-define=ENV=e2e` loads `frontend/envs/e2e.json`. It points the API at `127.0.0.1:18000` and the map tiles at the stub, and raises the API receive timeout from 3 to 20 seconds, because CI runners and the emulator are slower than production.

### Without Docker

`e2e/start-native.sh` (`make e2e-native-up`) runs the same stack directly on the machine. The iOS job uses it, because GitHub's macOS runners have no Docker. It needs uv, Node.js, Java 21+ and python3. Stop it with `make e2e-native-down`. Two differences from the Docker stack:

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

`journeys/monkey_journey.dart` isn't a journey: it's the monkey test (random taps, gestures and text), signed in on a device. `app_test.dart` runs it after the journeys when given `--dart-define=MONKEY=true`, as the nightly iOS and Android jobs do, and on Android `android-monkey.sh` then runs Android's own `adb shell monkey`. See "Monkey testing" in [TESTING.md](../TESTING.md#monkey-testing).

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

The iOS job runs the journeys through `e2e/run-ios.sh`. Now and then on CI, the simulator's `simctl launch` never returns after the build, so the app never starts (#63), and `flutter test` waits for it with no timeout. The script waits for the simulator to finish booting first. If no test has started 4 minutes after the build (it normally takes about 40 seconds), it stops that attempt and the app, reboots the simulator, and tries again, up to 3 times. Each attempt's output, and the simulator's log of the app for each one that didn't attach, go in the `e2e-failure-ios` artifact.

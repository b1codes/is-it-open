# Testing

How the automated checks are organized, how to run them locally, and what CI enforces.

## Quick reference

| Command | What it runs |
| --- | --- |
| `make check` | Every lint and test suite below (what CI runs on a PR) |
| `make lint` | ruff (backend and the E2E stub), mypy, `dart format`, `flutter analyze` |
| `make format` | Applies ruff fixes/formatting and `dart format` |
| `make test-backend` | Backend pytest suite against the Firestore emulator |
| `make test-frontend` | Flutter unit, bloc, and widget tests |
| `make test-widgetbook` | Widgetbook catalog smoke tests and accessibility checks (see [Accessibility](#accessibility)) |
| `make test-goldens` | Visual regression (golden) tests for every Widgetbook use case. They compare only on Linux and are skipped elsewhere |
| `make goldens-pull` | Replaces the goldens with the set CI regenerated for this branch, after an intended UI change (see [Visual regression](#visual-regression-frontendwidgetbook)) |
| `make coverage` | Both suites with coverage; fails below the minimums |
| `make mutation-backend` / `make mutation-frontend` | Mutation testing (slow; runs nightly in CI) |
| `make contracts-update` | Regenerates `contracts/openapi.json` after an intended API change |
| `make e2e` | The E2E journeys in headless Chrome, both layouts, against a stack it starts and stops (step by step: `make e2e-up`, `make test-e2e`, `make e2e-down`; see [e2e/README.md](e2e/README.md)) |

Backend targets run inside the dev container (`docker compose`), which starts the Firestore emulator for you. Frontend targets need the Flutter SDK on your machine. After a backend dependency changes, rebuild the container with `make build`.

## Backend (`backend/`)

- **Runner:** pytest with pytest-django. Tests live in `backend/tests/` and `backend/apps/*/tests*.py`:

  | Directory | What it covers |
  | --- | --- |
  | `tests/api/` | Every route in `config/api.py` through the Django test client: happy path, 422, 401, 404 |
  | `tests/repositories/` | `apps/*/repository.py` against the emulator: IDs, idempotency, transactions, per-user isolation |
  | `tests/services/` | `services/`: TomTom (mocked HTTP), geo math, Firestore helpers |
  | `tests/auth/` | `GlobalAuth`: local tokens, Auth0 JWT verification, the JWKS cache |
  | `tests/property/` | Hypothesis property tests (hours parsing, geo, document IDs, the search index) |
  | `tests/contracts/` | The API and TomTom contracts in `contracts/`: schema snapshot, Schemathesis provider tests, TomTom fixtures and the live check (see [contracts/README.md](contracts/README.md)) |

- **Database:** tests run against the emulator under a separate `demo-is-it-open-test` project, which is wiped before each test, so your local dev data is never touched. New tests use the `firestore_db` fixture (or a factory that depends on it); older ones subclass `tests.base.FirestoreTestCase`.
- **Fixtures** (`tests/conftest.py`):
  - Data: `make_user`, `make_place`, and `make_bookmark` factories, plus `user` and `place`. Payload builders are in `tests/factories.py`.
  - Clients: `api_client` (anonymous), `auth_client` (local API token), `auth0_client` (mock-mode Auth0 JWT), and `any_auth_client`, which runs a test once with each.
  - HTTP: `http_mock` ([responses](https://github.com/getsentry/responses)) fails any outbound request that isn't registered, so no test reaches a real service. `tomtom` enables `TomTomClient` with a test key. `auth0_tenant` turns off mock mode and serves an RS256 tenant's JWKS; sign tokens with `auth0_tenant.token(...)`.
  - An autouse fixture blanks `TOMTOM_API_KEY` and the Auth0 settings and clears the caches, so a local `.env` can't leak into a test.
- **Time:** use [freezegun](https://github.com/spulec/freezegun) (`freeze_time`), but keep Firestore calls outside the frozen block. The gRPC client hangs on a frozen clock.
- **Property tests:** the `HYPOTHESIS_PROFILE` environment variable picks the profile. Locally, `dev` draws 100 new examples per run. CI uses `ci`, a fixed set of 200, so a PR can't fail on a newly drawn example. The nightly run uses `nightly`, with 5,000 random examples. A failure prints `@reproduce_failure(...)`; add it to the test to replay the example.
- **Contract tests:** `SCHEMATHESIS_MAX_EXAMPLES` sets how many requests the provider tests send per operation (50 by default). The TomTom live tests run only when `TOMTOM_LIVE_API_KEY` is set.
- **Without Docker:** start the emulator (`docker compose up -d firestore`), then:

  ```sh
  cd backend
  FIRESTORE_EMULATOR_HOST=localhost:8080 GOOGLE_CLOUD_PROJECT=demo-is-it-open SECRET_KEY=test \
    uv run pytest
  ```

- **Lint/types:** `uv run ruff check .`, `uv run ruff format .`, `uv run mypy .` (config in `backend/pyproject.toml`).
- **Coverage:** `uv run pytest --cov` (branch coverage over `apps/`, `config/`, `services/`).

## Frontend (`frontend/`)

- **Runner:** `flutter test`. Tests mirror `lib/` under `test/` (`test/bloc/`, `test/services/`, `test/screens/`, ...); `test/main_test.dart` runs the whole app (startup, login, logout, sign-up) against a fake API.
- **Mocks:** [mocktail](https://pub.dev/packages/mocktail) only (no code generation). Shared mocks and fakes live in `test/helpers/mocks.dart`: `MockApiService`, `MockDeviceCalendarPlugin`, and fake Geolocator and FilePicker platforms (`FakeGeolocator.install(addTearDown, ...)`). Call `registerFallbacks()` in `setUpAll` before using `any()` with app types.
- **Widget tests:** `tester.pumpApp(widget)` (`test/helpers/pump_app.dart`) wraps a widget in a themed `MaterialApp` inside Widgetbook's `MockAppScope`: every app bloc and repository, backed by `FakeApiService` and the shared sample data (`test/helpers/fixtures.dart`). Options seed the auth state, calendar data, bookmarks, today's route, the 24-hour setting, failures and latency. Pass `api:` to serve requests from a mock; the auth and calendar-data blocs then use it too. Use `phoneSize`/`desktopSize` for layouts, and `tester.unmount()` to end a test that leaves timers running.
- **Fonts and network:** `test/flutter_test_config.dart` loads the timezone database and registers Roboto (from the Flutter SDK) in place of the runtime-fetched Google Fonts, so text lays out like a device and no test touches the network. Map tiles still log harmless `ClientException`s.
- **Time:** code that depends on "now" reads `clock.now()` ([package:clock](https://pub.dev/packages/clock)); pin it in tests with `withClock(Clock.fixed(...), () async { ... })`. CI runs the frontend job in `America/New_York` so date code is exercised across DST changes; the suite also passes in UTC.
- **Property tests:** [glados](https://pub.dev/packages/glados) checks open/closed status and availability windows against independent models (`test/utils/`). Each property gets its own `ExploreConfig`, whose fixed seed makes runs reproducible; a failure prints the shrunk input.
- **HTTP:** `test/helpers/fake_http_adapter.dart` is a Dio transport with a route table, for testing `ApiService` itself (`ApiService(httpClientAdapter: ...)`).
- **Contract tests:** `test/contracts/` runs every `ApiService` method against `ContractAdapter`, a fake backend generated from `../contracts/openapi.json` (see [contracts/README.md](contracts/README.md)). A new `ApiService` method needs an entry in `_calls` there.
- **Coverage:** `flutter test --coverage` only reports files a test imports, which hides untested screens. To count every file, run:

  ```sh
  dart run tool/coverage.dart imports            # generates test/coverage_imports_test.dart (gitignored)
  flutter test --coverage
  dart run tool/coverage.dart check --min=95     # per-file table; fails below the minimum
  ```

- **Lint:** `dart format lib test tool integration_test test_driver` and `flutter analyze lib test tool integration_test test_driver` (lints from `analysis_options.yaml`). Scope it to those directories: plain `flutter analyze` also picks up the nested `widgetbook/` package.

## Visual regression (`frontend/widgetbook/`)

`test/goldens_test.dart` renders every Widgetbook use case and compares it pixel for pixel with a PNG in `test/goldens/<use case>/`. Each use case gets 12 goldens: light and dark, at phone (390×844), tablet (834×1194) and desktop (1280×800) sizes, at text scale 1.0 and 2.0. Theme and text scale are set through the catalog's own addons, as a deep link into the catalog would set them.

- **What's captured:** screens fill the viewport. Components on a `ComponentStage`, and component dialogs, are cropped to the component, since the rest is the stage's backdrop.
- **Determinism:** text renders in the app's real fonts. Montserrat and Open Sans are bundled in `assets/google_fonts/`, as the exact files `google_fonts` would download (`tool/fetch_fonts.sh`), and runtime fetching is off, so a weight the app starts using without bundling it fails the tests. Roboto and the icon fonts are loaded too (`test/flutter_test_config.dart`). "Now" is pinned to Wednesday 10 June 2026, 10:30, and the tests require `TZ=UTC`.
- **Where they run:** font rasterization differs between operating systems and between Flutter engine versions. The goldens are therefore generated by the `Goldens` CI job, on `ubuntu-24.04` with Flutter 3.47.7 (pinned in `ci.yml`), and they're only compared on Linux. On macOS and Windows the tests are skipped.
- **Overflows:** a RenderFlex overflow fails the test, as it does in the accessibility checks.

### Updating the goldens

After an intended UI change, or after adding a use case:

1. Push. The `Goldens` job fails. Its run summary links two artifacts. **golden-failures** has, for each mismatch, the expected image (`_masterImage`), the rendered one (`_testImage`), and the differing pixels (`_isolatedDiff`, `_maskedDiff`). **goldens-updated** is the complete regenerated set.
2. Run `make goldens-pull` (or `make goldens-pull RUN=<run id>` for a specific run). It replaces `frontend/widgetbook/test/goldens/` with **goldens-updated** and lists what was added, changed and deleted.
3. Review the changed images (your Git client's image diff helps), then commit them.

Don't commit goldens rendered on macOS: they won't match CI. `flutter test --update-goldens` produces valid ones only on the pinned setup above.

To bump Flutter or the runner image for this job, change both in `ci.yml` in the same PR, then regenerate every golden with the steps above. A google_fonts upgrade that changes font files needs the same: re-run `tool/fetch_fonts.sh`, then regenerate.

## Accessibility

Two suites, both part of the regular CI jobs:

- **Every screen and component** (`frontend/widgetbook/test/accessibility_test.dart`, in the Widgetbook job): each catalog use case, in light and dark at phone and desktop widths, must meet Flutter's accessibility guidelines: tap targets of at least 48×48 (`androidTapTargetGuideline`) and 44×44 (`iOSTapTargetGuideline`), a label on everything tappable (`labeledTapTargetGuideline`), and WCAG AA text contrast (`textContrastGuideline`: 4.5:1, or 3:1 for large text). Each use case must also lay out at 2× text, at phone, tablet and desktop widths, without overflowing. These run on every platform.
- **App behavior** (`frontend/test/accessibility/`, in the Frontend job): what a screen reader gets (labels on icon-only buttons, status pills that say the status in words, map markers it can reach and press); reduced motion (with the system setting on, `MediaQuery.disableAnimations`, transitions are instant); and WCAG AA contrast for the theme's text colors, computed from the colors themselves.

When you add something:

- **An icon-only button:** give it a `tooltip`. That's its spoken label too.
- **An animation:** take its duration from `PlacesMotion.of(context, duration)`, which is zero under reduced motion. Skip purely decorative effects when `MediaQuery.disableAnimationsOf(context)` is true.
- **Text in a `Row`:** wrap it in `Flexible` or `Expanded` so it can wrap or truncate at 2× text. For a fixed-height container, size it from `MediaQuery.textScalerOf(context)` (see `SavedPlaceTile.gridExtent`).
- **A new text color:** add the pair to `test/accessibility/contrast_test.dart`.

The contrast guideline measures rendered pixels: it takes the two most common colors around a piece of text as text and background. That misreads small text on a busy background (the calendar grid, a gradient, the catalog's glass backdrop). Such cases are listed in `_contrastExempt` in `accessibility_test.dart`, each with its reason; check them by hand before adding one. Calendar event blocks are exempt from the tap target size, since their height is the event's duration; `CalendarEventTileWidget.semanticsIdentifier` marks them.

What automation can't check (TalkBack and VoiceOver reading order, and how the app feels with them on a device) stays manual.

## E2E (`frontend/integration_test/`, `e2e/`)

The real app, driven through its UI, against the production backend image, the Firestore emulator, and a stub for TomTom, the iCal feed and map tiles. The journeys cover sign-up, sign-in and session restore; the profile and home address; search; the bookmark lifecycle; quick add; settings across a restart; the calendar subscription; and error paths (backend down, TomTom outage, revoked session). Run them with `make e2e`. Details, including how to write a journey, are in [e2e/README.md](e2e/README.md).

## CI (`.github/workflows/`)

| Workflow | When | Jobs |
| --- | --- | --- |
| `ci.yml` | Every PR and push to `main` | `backend`, `frontend`, `widgetbook` and `goldens` run in parallel. Each runs only when its paths change (both backend and frontend run when `contracts/` changes). `E2E (desktop)` and `E2E (phone)` run the journeys in headless Chrome when the backend, frontend or E2E files change. On PRs that change `contracts/`, `API breaking changes` diffs the API contract against the base branch. The `ci` job is the required check and passes only if every job passed or was skipped. |
| `test-report.yml` | After CI or Nightly | Publishes test results as check runs on the commit |
| `nightly.yml` | 07:00 UTC daily, or manually | Quarantined tests, backend property tests with 5,000 examples each, API contract fuzzing with 1,000 requests per operation, the live TomTom contract check (needs a `TOMTOM_API_KEY` secret), the E2E journeys on an iOS simulator and an Android emulator (`e2e-mobile.yml`), and mutation testing (non-blocking) |

Each job writes a coverage table to its run summary. On PRs it also reports diff coverage, meaning coverage of just the changed lines. Diff coverage is informational for now.

### Coverage minimums

| Suite | Minimum | Goal |
| --- | --- | --- |
| Backend | 95% | 95% |
| Frontend | 95% | 95% |

The minimums are set in `ci.yml` (`BACKEND_MIN_COVERAGE`, `FRONTEND_MIN_COVERAGE`) and mirrored in the `Makefile`. **Ratchet them up** as coverage grows, and never lower them to get a PR through.

## Flaky tests

1. CI retries a failing test once (`--reruns 1` for pytest, `retry: 1` appended to `dart_test.yaml`). Locally there is no retry, so a flaky test shows up the first time it fails.
2. If a test keeps flaking, quarantine it and open a ClickUp task to fix it:
   - pytest: `@pytest.mark.quarantine`
   - Flutter: `test('...', () {...}, tags: 'quarantine')`
3. Quarantined tests are skipped by the required CI job and run nightly, so they stay visible. Remove the marker once the test is fixed.

## Mutation testing

Mutation testing makes small changes to the code (flip a `<`, drop a `return`, swap `&&` for `||`) and checks that some test fails. A mutant that survives points to logic the tests run but don't actually check.

- **Backend:** [mutmut](https://mutmut.readthedocs.io/) over `apps/` and `services/` (config under `[tool.mutmut]` in `pyproject.toml`). View a survivor with `uv run mutmut show <name>`. On macOS, set `OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES` if workers crash.
- **Frontend:** [mutation_test](https://pub.dev/packages/mutation_test) over the pure-Dart logic listed in `frontend/mutation_test.xml`.

## Pre-commit hooks (optional)

```sh
uvx pre-commit install
```

This runs ruff and `dart format` on staged files before each commit, using the same tool versions as CI.

# Testing

How the automated checks are organized, how to run them locally, and what CI enforces. What they can't check (native permission prompts, device pickers, screen readers, real-device feel) is in the [manual QA checklist](MANUAL_QA.md).

## Quick reference

| Command | What it runs |
| --- | --- |
| `make check` | Every lint and test suite below (what CI runs on a PR) |
| `make lint` | ruff (backend, the E2E stub and the smoke test), mypy, bandit, `dart format`, `flutter analyze`, and the Terraform checks (`make lint-infra`; see [Infrastructure](#infrastructure)) |
| `make audit` | Known vulnerabilities in the locked dependencies: pip-audit and osv-scanner (see [Security](#security)) |
| `make format` | Applies ruff fixes/formatting and `dart format` |
| `make test-backend` | Backend pytest suite against the Firestore emulator |
| `make test-frontend` | Flutter unit, bloc, and widget tests |
| `make test-monkey` | The monkey test: the whole app under seeded random input, as CI runs it. `SEED=` replays a run, `STEPS=` sets the actions per scenario, `NAME=` picks one scenario (see [Monkey testing](#monkey-testing)) |
| `make test-widgetbook` | Widgetbook catalog smoke tests and accessibility checks (see [Accessibility](#accessibility)) |
| `make test-goldens` | Visual regression (golden) tests for every Widgetbook use case. They compare only on Linux and are skipped elsewhere |
| `make goldens-pull` | Replaces the goldens with the set CI regenerated for this branch, after an intended UI change (see [Visual regression](#visual-regression-frontendwidgetbook)) |
| `make coverage` | Both suites with coverage; fails below the minimums |
| `make mutation-backend` / `make mutation-frontend` | Mutation testing (slow; runs nightly in CI) |
| `make test-rules` | The Firestore security rules tests against the emulator (see [Infrastructure](#infrastructure)) |
| `make smoke URL=...` / `make test-smoke` | The post-deploy smoke test against a deployed backend / a running E2E stack (see [smoke/README.md](smoke/README.md)) |
| `make contracts-update` | Regenerates `contracts/openapi.json` after an intended API change |
| `make load` | The API load test against an E2E stack it starts and stops (see [Performance](#performance)) |
| `make perf-frames` | Frame timing of the map, calendar and search, against a running E2E stack (Linux) |
| `make app-size` / `make app-size-pull` | Release build sizes against the baseline / accept the sizes CI measured |
| `make e2e` | The E2E journeys in headless Chrome, both layouts, against a stack it starts and stops (step by step: `make e2e-up`, `make test-e2e`, `make e2e-down`; see [e2e/README.md](e2e/README.md)) |

Backend targets run inside the dev container (`docker compose`), which starts the Firestore emulator for you. Frontend targets need the Flutter SDK on your machine: the version pinned in `.fvmrc`, which CI uses too. With [FVM](https://fvm.app) installed, `fvm install` fetches it and the targets run it through `fvm flutter`; without FVM they use the `flutter` on your `PATH`. After a backend dependency changes, rebuild the container with `make build`.

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
  | `tests/security/` | Authorization across users, the auth settings, forged JWTs, and SSRF in the calendar proxy (see [Security](#security)) |
  | `tests/performance/` | Firestore reads, writes and round trips per request, and no N+1 reads (see [Performance](#performance)) |
  | `tests/deploy/` | `/health`, and the production settings and entrypoint checks (see [Infrastructure](#infrastructure)) |

- **Database:** tests run against the emulator under a separate `demo-is-it-open-test` project, which is wiped before each test, so your local dev data is never touched. New tests use the `firestore_db` fixture (or a factory that depends on it); older ones subclass `tests.base.FirestoreTestCase`.
- **Fixtures** (`tests/conftest.py`):
  - Data: `make_user`, `make_place`, and `make_bookmark` factories, plus `user` and `place`. Payload builders are in `tests/factories.py`.
  - Clients: `api_client` (anonymous), `auth_client` (local API token), `auth0_client` (mock-mode Auth0 JWT), and `any_auth_client`, which runs a test once with each.
  - HTTP: `http_mock` ([responses](https://github.com/getsentry/responses)) fails any outbound request that isn't registered, so no test reaches a real service. `tomtom` enables `TomTomClient` with a test key. `auth0_tenant` turns off mock mode and serves an RS256 tenant's JWKS; sign tokens with `auth0_tenant.token(...)`.
  - DNS: `dns` (autouse) fakes name lookups for `services/safe_fetch.py`, so the calendar proxy's address check never looks a name up. Unknown names resolve to a public address; add entries to point a name elsewhere (`dns["feed.example.com"] = ["10.0.0.1"]`).
  - An autouse fixture blanks `TOMTOM_API_KEY` and the Auth0 settings (mock mode off, as in production) and clears the caches, so a local `.env` can't leak into a test.
- **Time:** use [freezegun](https://github.com/spulec/freezegun) (`freeze_time`), but keep Firestore calls outside the frozen block. The gRPC client hangs on a frozen clock.
- **Property tests:** the `HYPOTHESIS_PROFILE` environment variable picks the profile. Locally, `dev` draws 100 new examples per run. CI uses `ci`, a fixed set of 200, so a PR can't fail on a newly drawn example. The nightly run uses `nightly`, with 5,000 random examples. A failure prints `@reproduce_failure(...)`; add it to the test to replay the example.
- **Contract tests:** `SCHEMATHESIS_MAX_EXAMPLES` sets how many requests the provider tests send per operation (50 by default). The TomTom live tests run only when `TOMTOM_LIVE_API_KEY` is set.
- **Without Docker:** start the emulator (`docker compose up -d firestore`), then:

  ```sh
  cd backend
  FIRESTORE_EMULATOR_HOST=localhost:8080 GOOGLE_CLOUD_PROJECT=demo-is-it-open SECRET_KEY=test \
    uv run pytest
  ```

- **Lint/types:** `uv run ruff check .`, `uv run ruff format .`, `uv run mypy .`, `uv run bandit -c pyproject.toml -r . -x '*/tests.py,*/tests_*.py'` (config in `backend/pyproject.toml`).
- **Coverage:** `uv run pytest --cov` (branch coverage over `apps/`, `config/`, `services/`).

## Frontend (`frontend/`)

- **Runner:** `flutter test`. Tests mirror `lib/` under `test/` (`test/bloc/`, `test/services/`, `test/screens/`, ...); `test/main_test.dart` runs the whole app (startup, login, logout, sign-up) against a fake API.
- **Edge cases** (`test/edge_cases/`): impatient and unusual use of the main screens, which the [monkey test](#monkey-testing) explores at random. Double taps on submit, and taps while a request is out, send one request (`repeated_taps`). Leaving a screen mid-request and the app going to the background are harmless (`interruptions`). A phone turned on its side, and 2× text in either orientation, lay out (`layout_changes`). Offline and on a network that never answers, every tab says so or keeps loading (`network`). Emoji, RTL, markup and very long strings reach the API as typed and lay out (`text_input`). `RecordingApi` (`test/helpers/recording_api.dart`) records the requests a `FakeApiService` gets.
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
- **Where they run:** font rasterization differs between operating systems and between Flutter engine versions. The goldens are therefore generated by the `Goldens` CI job, on `ubuntu-24.04` with the Flutter version pinned in `.fvmrc`, and they're only compared on Linux. On macOS and Windows the tests are skipped.
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

- **Every screen and component** (`frontend/widgetbook/test/accessibility_test.dart`, in the Widgetbook job): each catalog use case, in light and dark at phone and desktop widths, must meet Flutter's tap target guidelines: at least 48×48 (`androidTapTargetGuideline`) and 44×44 (`iOSTapTargetGuideline`), and a label on everything tappable (`labeledTapTargetGuideline`). Its text must meet WCAG AA contrast: 4.5:1, or 3:1 for large text. Each use case must also lay out at 2× text, at phone, tablet and desktop widths, without overflowing. These run on every platform.
- **App behavior** (`frontend/test/accessibility/`, in the Frontend job): what a screen reader gets (labels on icon-only buttons, status pills that say the status in words, map markers it can reach and press); reduced motion (with the system setting on, `MediaQuery.disableAnimations`, transitions are instant); and WCAG AA contrast for the theme's text colors, computed from the colors themselves.

When you add something:

- **An icon-only button:** give it a `tooltip`. That's its spoken label too.
- **An animation:** take its duration from `PlacesMotion.of(context, duration)`, which is zero under reduced motion. Skip purely decorative effects when `MediaQuery.disableAnimationsOf(context)` is true.
- **Text in a `Row`:** wrap it in `Flexible` or `Expanded` so it can wrap or truncate at 2× text. For a fixed-height container, size it from `MediaQuery.textScalerOf(context)` (see `SavedPlaceTile.gridExtent`).
- **A new text color:** add the pair to `test/accessibility/contrast_test.dart`.

Contrast is checked by `TextStyleContrastGuideline` (`test/support/text_contrast.dart`), not Flutter's `textContrastGuideline`. Flutter's takes the two most common colors around a piece of text as text and background, which depends on how the platform anti-aliases glyphs. On CI's Linux runner it read ink on paper as 1.5:1. Ours takes the text's color from its style and reads only the background from the rendered pixels. It skips icons, disabled controls, and transparent or covered text. The only use cases it doesn't check are components shown on the catalog's multicolor glass backdrop (`_contrastExempt`). Calendar event blocks are exempt from the tap target size, since their height is the event's duration on the time grid.

What automation can't check (TalkBack and VoiceOver reading order, and how the app feels with them on a device) stays manual; see [MANUAL_QA.md](MANUAL_QA.md).

## Security

- **Tests** (`backend/tests/security/`, in the Backend job):
  - `test_authorization.py`: every operation in the served schema is either public (login, register) or needs sign-in, and rejects anonymous callers. Alice runs every `/auth/me` and `/places/bookmarks*` route against data Bob also has, and his profile and bookmarks stay unchanged and never appear in her responses. A new operation fails until it's classified, and a new bookmark route until it's in the cross-user checks.
  - `test_auth_config.py`: `AUTH0_MOCK` is off unless set, and the settings refuse to load with it on and `DEBUG` off. Without `AUTH0_DOMAIN` every Auth0 token is rejected. Each case imports the settings in a fresh interpreter, with no `.env`.
  - `test_jwt.py`: forged and invalid tokens (`alg=none`, stripped or wrong signatures, HS256 signed with the public key, tampered payloads, `jwk`/`jku`/`x5u` key injection, wrong issuer or audience, expired, not yet valid, no `exp` or `sub`) are all a 401 and create no account.
  - `test_ssrf.py`: `/calendar/proxy` only fetches from public addresses (`services/safe_fetch.py`). It refuses the metadata service, loopback, private and reserved ranges in every spelling, names that resolve to them, and redirects to them. It connects to the address it checked, so DNS rebinding fails too. It ignores proxy environment variables and returns only iCalendar files, up to 10 MB, within 30 seconds. Most cases use `http_mock` and the fake `dns`; the connection-time checks use a real server on 127.0.0.1. The E2E stack lets the proxy reach its stub with `SAFE_FETCH_PRIVATE_HOSTS`, which nothing else should set.
- **Static analysis:** bandit runs in the Backend job and `make lint`, on app code only. Any finding fails it, so mark a deliberate one `# nosec <id>`, with the reason in a comment on the line above (bandit reads words after `nosec` as rule IDs). CodeQL (`codeql.yml`) analyzes the backend and the workflows on every PR, push to `main` and weekly, with the `security-extended` queries. Results are under Security > Code scanning. GitHub's secret scanning and push protection are on in the repository settings.
- **Dependencies:** `dependency-audit.yml` runs pip-audit on the backend's locked packages, all groups, and osv-scanner on `backend/uv.lock`, the app's and Widgetbook's `pubspec.lock`, and the Firestore rules tests' `package-lock.json`. Those two aren't committed, so the job runs `flutter pub get` first, as the Flutter jobs do. CI runs the audit when `pyproject.toml`, `uv.lock` or a `pubspec.yaml` changes, as part of the required check, and nightly for advisories published since. `make audit` runs it locally, against your own `pubspec.lock` files. Fix a finding by upgrading the package (`uv lock --upgrade-package <name>`, or `flutter pub upgrade <name>`).
- **DAST** (nightly): OWASP ZAP's API scan, driven by the served OpenAPI schema (the one in `contracts/openapi.json`) and signed in as the seeded account. There's no staging backend yet, so it scans the E2E stack, which runs the production image. Any alert fails the job unless `.zap/rules.tsv` accepts it, with a reason. The HTML report is in the `zap-report` artifact. To run it locally, with the stack up (`make e2e-up`), pass a token from `POST /api/auth/login` as `ZAP_AUTH_HEADER_VALUE="Bearer <token>"` and `ZAP_AUTH_HEADER_SITE=host.docker.internal` to `docker run -v "$PWD/.zap:/zap/wrk" ghcr.io/zaproxy/zaproxy:2.17.0 zap-api-scan.py -t http://host.docker.internal:18000/api/openapi.json -f openapi -c rules.tsv`.
- **Not covered yet:** rate limiting, which isn't implemented ([its ClickUp task](https://app.clickup.com/t/86ba3a34w)). Add tests for it in `tests/security/` when it lands.

## Performance

The Firestore cost tests run per PR. The rest run nightly in `perf.yml` (or by hand: Actions > Performance > Run workflow), since timings need a full-length run, and none of them block a merge.

- **Firestore cost** (`backend/tests/performance/`, in the Backend job): the `firestore_usage` fixture counts the document reads and writes a block of code makes, which is what Firestore bills, and its round trips, which is what the user waits for. It wraps the client library's RPC layer, so it counts every call, from any thread. A read is each document a query returns (at least one per query, even an empty one) and each document looked up by reference, found or not. `test_firestore_cost.py` pins the cost of a typical request to every operation in the served schema, so a new route fails until it has an entry. It also checks that the list routes (bookmarks, nearby, suggestions, search) make a fixed number of round trips however much data there is, and that search stops at its candidate limit. When a route should cost more, or less, update its entry in `EXPECTED_COSTS`.
- **API load test** (`perf/load.js`, [k6](https://grafana.com/docs/k6/)): 20 users, each with their own account, for 2 minutes. Each session searches, gets nearby places and suggestions, then saves a place, bookmarks it, lists bookmarks, pins it and removes it. Setup adds 200 places around Manhattan, so nearby and search read a realistic amount. It runs against the E2E stack, the production image with TomTom stubbed, since there's no staging backend yet. The run fails if any endpoint's p95 latency is over its budget in `BUDGETS`, or more than 1% of requests fail. The budgets are about twice the slowest of three GitHub runner runs (runners varied by up to 4×), so they catch regressions rather than describe production latency. Search and nearby have looser budgets, because they return every match ([#51](https://github.com/b1codes/is-it-open/issues/51)). The latency table is in the run summary, and the full k6 results are in the `load-test` artifact. Locally, `make load` starts the stack, runs the test and stops the stack (`make test-load` uses a running stack). `VUS`, `DURATION` and `PLACES` override the defaults, e.g. `make load VUS=60 DURATION=30s`. It runs k6 from its Docker image, so there's nothing to install.
- **Frame timing** (`frontend/integration_test/perf_test.dart`): pans and pinch-zooms the map with 40 pinned places, scrolls the calendar's hours and pages its weeks, and types a search one letter at a time. Each runs in `traceAction`, so the app must run in profile mode on a desktop: the web has no VM timeline, and emulators don't run profile builds. CI runs it as a Linux desktop app under `xvfb`. `test_driver/perf_driver.dart` summarizes each timeline and checks two budgets per interaction, in `_budgets`. The first is the share of frames that took over 16 ms to build, i.e. dropped below 60 fps on the UI thread. That's the app's own work, and it janks on any device. The second is the 90th percentile raster time. CI rasterizes in software, far slower than a phone's GPU (the glass blurs most of all), so raster times only compare one CI run with another; that budget is about twice what a runner measured. The table is in the run summary, and the timelines are in the `frame-timing` artifact (open one in [Perfetto](https://ui.perfetto.dev)). Profile builds don't route the keyboard through the test's text input, so the search interaction registers it before typing. To run it on Linux: `make e2e-up`, then `make perf-frames`. macOS can't build the app with Xcode 26+ ([#45](https://github.com/b1codes/is-it-open/issues/45)), and couldn't reach the API anyway ([#52](https://github.com/b1codes/is-it-open/issues/52)).
- **App size** (`frontend/tool/app_size.dart`): builds the release arm64 APK (`flutter build apk --analyze-size`) and the web app, then compares them with the baseline in `frontend/app_size.json`. It fails if either grows by more than 5%. The web build is counted without CanvasKit, the 26 MB renderer that only a Flutter upgrade changes. The table also shows where a change came from: Dart code, engine, assets and dex for the APK, and `main.dart.js` and assets for the web. Sizes differ between Flutter versions, so the baseline is measured by CI with the version pinned in `.fvmrc`. After an intended change, a dependency added, or a Flutter bump, run the workflow, check the sizes in its summary, then run `make app-size-pull` (or `make app-size-pull RUN=<run id>`) and commit `frontend/app_size.json`. The same applies when it shrinks by more than 5%, so the savings can't quietly grow back. `make app-size` measures locally, against your own Flutter.

## Infrastructure

Checks on what surrounds the code: the production image, its settings, the Firestore rules, `infra/`, and the deployed backend.

- **`/health`** (`backend/config/health.py`): a liveness check for Docker, load balancers and the smoke test. It answers `GET` and `HEAD /health` with `{"status": "ok"}` before Django checks the `Host` header, since probes reach the container as `localhost` or by IP, which production's `ALLOWED_HOSTS` doesn't list. It doesn't touch Firestore, so a slow database doesn't make a running container look dead. The smoke test checks Firestore instead. `docker-compose.prod.yml` uses it as the backend's healthcheck.
- **Production settings** (`backend/tests/deploy/test_settings.py`, in the Backend job): `backend/sample.env`, which the deploy guide says to copy, loads with `docker-compose.prod.yml`'s overrides as a locked-down config: `DEBUG` off, no emulator, CORS closed, Auth0 mock mode off. `SECRET_KEY` is required, `ALLOWED_HOSTS` is a comma-separated list, and requests for another host (400) or origin (no CORS headers) are refused. The compose file's entrypoint script runs as-is for each setting it refuses (an empty or missing `SECRET_KEY` or `GOOGLE_CLOUD_PROJECT`, a `demo-*` project, an empty `FIRESTORE_DATABASE`, a missing key file). The dev container mounts `docker-compose.prod.yml` so these tests can read it. A `.env` without the `ALLOWED_HOSTS` line still starts, accepting any host ([#54](https://github.com/b1codes/is-it-open/issues/54)).
- **Production image** (`production-image.yml`, from `ci.yml` when the backend changes and from `nightly.yml`): builds and starts `docker-compose.prod.yml` with `sample.env`, as the deploy guide does, and waits for the healthcheck. It checks that the API refuses hosts `ALLOWED_HOSTS` doesn't list, that a 404 isn't Django's debug page, that CORS is closed, and that the entrypoint refuses an empty `SECRET_KEY`. Then [Trivy](https://trivy.dev) scans the image. A HIGH or CRITICAL vulnerability with a fix (in Debian or Python packages), or a secret in the image, fails the job. Unfixed CVEs in the base image are listed in the summary but don't fail it, since there's nothing to upgrade to and the base image is pulled fresh on every build. Fix a finding by rebuilding (a newer base image), upgrading the package (`uv lock --upgrade-package <name>`), or removing it from the image, as the Dockerfile does with the base image's unused setuptools and wheel. Nightly runs catch CVEs published since the last change.
- **Firestore rules** (`docker/firestore-emulator/rules-test/`, the `Firestore rules` job, when `docker/firestore-emulator/` changes): `firestore.rules` must deny every direct client read and write, because only the backend reaches Firestore, through the server client library, which bypasses the rules. [`@firebase/rules-unit-testing`](https://www.npmjs.com/package/@firebase/rules-unit-testing) loads the rules into the emulator, seeds the collections the backend uses, and tries each kind of client access: get, list, query, collection group, create, overwrite, merge, update, delete, batch and transaction. It does this signed out, signed in, signed in as the document's owner, and with verified-email or admin claims. After each test the seeded data must be unchanged. `make test-rules` runs it (it needs Node.js 22+). `package.json` overrides `@grpc/grpc-js` to 1.13.6, since `firebase` 12.19 pins a version with known advisories; drop the override once a `firebase` upgrade brings a fixed version. The rules only apply to the emulator. A production database keeps whatever rules its project has.
- **Terraform** (`infra/`, the `Terraform` job, when `infra/` changes): `terraform fmt -check`, `terraform validate` (initialized without a backend, so CI never touches state), [tflint](https://github.com/terraform-linters/tflint) with the recommended Terraform rules (`infra/.tflint.hcl`), and `trivy config`, the successor to tfsec, which fails on a HIGH or CRITICAL misconfiguration such as a public bucket or an open firewall rule. `infra/` is still a commented-out AWS skeleton, so for now these checks mostly gate the [GCP migration](https://app.clickup.com/t/86bazmf6y). When it lands, add the provider's tflint ruleset (`tflint-ruleset-google`) to `.tflint.hcl`. `make lint-infra` runs the same checks in Docker, with the same versions.
- **Post-deploy smoke test** (`smoke/`): checks a deployed backend's health, sign-in, search and a bookmark round trip with a test account. The E2E job runs it against the E2E stack on every PR that touches the app, the stack or `smoke/`. `smoke.yml` runs it against production every hour and on demand after a deploy, and opens a `smoke-failure` issue when it fails. Deploys are manual for now, so nothing runs it automatically after one or rolls back on failure ([#53](https://github.com/b1codes/is-it-open/issues/53)). What it reports when a check fails is tested against a fake backend in `backend/tests/deploy/test_smoke.py` (the dev container mounts `smoke/` at `/smoke` for it). Setup and details are in [smoke/README.md](smoke/README.md).

## E2E (`frontend/integration_test/`, `e2e/`)

The real app, driven through its UI, against the production backend image, the Firestore emulator, and a stub for TomTom, the iCal feed and map tiles. The journeys cover sign-up, sign-in and session restore; the profile and home address; search; the bookmark lifecycle; quick add; settings across a restart; the calendar subscription; and error paths (backend down, TomTom outage, revoked session). Run them with `make e2e`. Details, including how to write a journey, are in [e2e/README.md](e2e/README.md).

## Monkey testing

Random input, the kind a scripted test never sends: a seeded "monkey" drives the whole app and fails on the first exception, layout overflow, or empty navigator (a screen popped twice).

- **The harness** (`frontend/integration_test/helpers/monkey.dart`, shared by the widget and device runs): each step picks an action. That's a tap on something tappable a little off its center (a fat finger), a tap anywhere, a double tap, rapid taps, a long press, a drag or fling, a two-finger pinch, two fingers tapping two things at once, random text in a field (emoji, combining marks, RTL and CJK text, control characters, markup, SQL, very long strings), sometimes submitted, the back button, the app going to the background and back, the phone turning, the system text size (up to 2×), or light and dark. After each step it waits a random time, from a frame to most of a second, so the next action lands mid-request or mid-transition as often as on a settled screen. `avoid` keeps it off labels like "Logout".
- **Widget tests** (`frontend/test/monkey/monkey_test.dart`, tag `monkey`): the app (`MyApp`) on `FakeApiService`, with "now" pinned, so a seed replays exactly. Five scenarios: signed out on a phone, signed in on a phone and on a desktop, a slow network (3 s per request) and offline. Each takes its seed from `--dart-define=SEED` mixed with its name, and `--dart-define=MONKEY_STEPS` sets the actions per scenario.
- **On failure** the test prints the error (which widget threw, and the stack), the last 25 actions, and the command that replays the run. Each scenario writes its full action log to `frontend/build/monkey/<scenario>.log` as it goes, so a run that hangs leaves one too, and saves a screenshot to `<scenario>.png` when it fails. `make test-monkey SEED=<seed> STEPS=<steps> NAME="<scenario>"` replays one locally.
- **Per PR:** the Frontend job runs it as its own step (not part of the coverage run) with the default seed and 1,000 steps per scenario, about two minutes on a runner. A fixed seed means a PR can't fail on a newly drawn sequence; a failure there is a regression.
- **Nightly:** `nightly.yml` runs 18,000 steps per scenario with a random seed, about 25 minutes. The run summary has the seed and the replay command, and the **monkey-nightly** artifact has the logs and screenshot. To rerun a night with its seed, run the workflow by hand with `monkey_seed`.
- **On devices** (`frontend/integration_test/journeys/monkey_journey.dart`, nightly in `e2e-mobile.yml`): the same harness on the iOS simulator and the Android emulator, run by `app_test.dart` after the journeys when it gets `--dart-define=MONKEY=true`, so each device builds and launches the test app once, for 800 steps, against the E2E stack, signed in as an account of its own. It stays off whatever ends the run early: signing out, and anything that opens a native file picker or permission prompt. Requests take real time here, so a seed replays the same choices but not always the same screens. Each step gets 60 seconds; a stuck one fails naming the step, and every action is logged as it starts, so a hang shows where it happened. On Android, `e2e/android-monkey.sh` then runs Android's own monkey (`adb shell monkey`, 5,000 events with the same seed) on a debug build, through the OS's input system. It fails on a crash, an ANR, or a Flutter error in logcat. Its logs are in the **e2e-failure-android** artifact.
- **Flutter's bugs:** a debug assertion inside Flutter that the app can't avoid is skipped and noted in the action log if it's in `knownFlutterBugs` (in `monkey.dart`, mirrored by the `known` list in `e2e/android-monkey.sh`). One is left: `'_hold == null'` when a phone sheet left between snap sizes is tapped ([flutter/flutter#172174](https://github.com/flutter/flutter/issues/172174)). The app avoids the other two it used to skip, each workaround commented where it lives ([#61](https://github.com/b1codes/is-it-open/issues/61)). Password fields get no emoji, which Flutter mishandles ([#60](https://github.com/b1codes/is-it-open/issues/60)). Remove each workaround once the Flutter version in `.fvmrc` fixes it.
- **When it finds a bug:** fix it, and add a small deterministic test for it next to the code's other tests, not in the monkey. If it's Flutter's, first look for a small change in the app that avoids it. If there isn't one, file an issue upstream and add it to `knownFlutterBugs` (and `android-monkey.sh`) with a matcher as narrow as the error allows.
- **The API** gets the same treatment from Schemathesis, which sends generated and invalid requests to every operation in the contract (see [contracts/README.md](contracts/README.md)).

## CI (`.github/workflows/`)

| Workflow | When | Jobs |
| --- | --- | --- |
| `ci.yml` | Every PR and push to `main` | `backend`, `frontend`, `widgetbook` and `goldens` run in parallel. Each runs only when its paths change (both backend and frontend run when `contracts/` changes). `E2E (desktop)` and `E2E (phone)` run the journeys in headless Chrome when the backend, frontend or E2E files change, and the desktop leg then runs the smoke test against the same stack. `Production image` boots and scans the backend image when the backend changes, `Firestore rules` tests the rules when `docker/firestore-emulator/` changes, and `Terraform` checks `infra/` when it changes (see [Infrastructure](#infrastructure)). On PRs that change `contracts/`, `API breaking changes` diffs the API contract against the base branch. When the dependencies change, `Dependency audit` checks them for known vulnerabilities. The `frontend` job also runs the monkey test with a fixed seed (see [Monkey testing](#monkey-testing)). The `ci` job is the required check and passes only if every job passed or was skipped. |
| `codeql.yml` | Every PR, push to `main`, and weekly | CodeQL for Python and the workflows (see [Security](#security)) |
| `test-report.yml` | After CI or Nightly | Publishes test results as check runs on the commit |
| `smoke.yml` | Hourly, manually after a deploy, or from a deploy workflow | The post-deploy smoke test against `SMOKE_BASE_URL` (skipped until it's set), with a `smoke-failure` issue on failure (see [smoke/README.md](smoke/README.md)) |
| `perf.yml` | Nightly (from `nightly.yml`), or manually | The API load test, frame timing, and the app size check (see [Performance](#performance)) |
| `nightly.yml` | 07:00 UTC daily, or manually | Quarantined tests, backend property tests with 5,000 examples each, API contract fuzzing with 1,000 requests per operation, the live TomTom contract check (needs a `TOMTOM_API_KEY` secret), a long monkey test with a random seed, the E2E journeys and the monkey test on an iOS simulator and an Android emulator (`e2e-mobile.yml`), mutation testing, the dependency audit (`dependency-audit.yml`), the production image scan (`production-image.yml`), the ZAP API scan (`dast.yml`), and the performance checks (`perf.yml`). None of them block a merge |

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

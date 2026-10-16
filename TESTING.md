# Testing

How the automated checks are organized, how to run them locally, and what CI enforces.

## Quick reference

| Command | What it runs |
| --- | --- |
| `make check` | Every lint and test suite below (what CI runs on a PR) |
| `make lint` | ruff, mypy, `dart format`, `flutter analyze` |
| `make format` | Applies ruff fixes/formatting and `dart format` |
| `make test-backend` | Backend pytest suite against the Firestore emulator |
| `make test-frontend` | Flutter unit, bloc, and widget tests |
| `make test-widgetbook` | Widgetbook catalog smoke tests |
| `make coverage` | Both suites with coverage; fails below the minimums |
| `make mutation-backend` / `make mutation-frontend` | Mutation testing (slow; runs nightly in CI) |

Backend targets run inside the dev container (`docker compose`), which starts the Firestore emulator for you. Frontend targets need the Flutter SDK on your machine.

## Backend (`backend/`)

- **Runner:** pytest with pytest-django. Tests live in `backend/tests/` and `backend/apps/*/tests*.py`.
- **Database:** every test case subclasses `tests.base.FirestoreTestCase`. It runs against the emulator under a separate `demo-is-it-open-test` project, which is wiped before each test, so your local dev data is never touched.
- **Without Docker:** start the emulator (`docker compose up -d firestore`), then:

  ```sh
  cd backend
  FIRESTORE_EMULATOR_HOST=localhost:8080 GOOGLE_CLOUD_PROJECT=demo-is-it-open SECRET_KEY=test \
    uv run pytest
  ```

- **Lint/types:** `uv run ruff check .`, `uv run ruff format .`, `uv run mypy .` (config in `backend/pyproject.toml`).
- **Coverage:** `uv run pytest --cov` (branch coverage over `apps/`, `config/`, `services/`).

## Frontend (`frontend/`)

- **Runner:** `flutter test`. Tests mirror `lib/` under `test/`.
- **Coverage:** `flutter test --coverage` only reports files a test imports, which hides untested screens. To count every file, run:

  ```sh
  dart run tool/coverage.dart imports            # generates test/coverage_imports_test.dart (gitignored)
  flutter test --coverage
  dart run tool/coverage.dart check --min=13     # per-file table; fails below the minimum
  ```

- **Lint:** `dart format lib test tool` and `flutter analyze` (lints from `analysis_options.yaml`).

## CI (`.github/workflows/`)

| Workflow | When | Jobs |
| --- | --- | --- |
| `ci.yml` | Every PR and push to `main` | `backend`, `frontend`, and `widgetbook` run in parallel. Each runs only when its paths change. The `ci` job is the required check and passes only if every job passed or was skipped. |
| `test-report.yml` | After CI or Nightly | Publishes test results as check runs on the commit |
| `nightly.yml` | 07:00 UTC daily, or manually | Quarantined tests and mutation testing (non-blocking) |

Each job writes a coverage table to its run summary. On PRs it also reports diff coverage, meaning coverage of just the changed lines. Diff coverage is informational for now.

### Coverage minimums

| Suite | Minimum | Goal |
| --- | --- | --- |
| Backend | 80% | 85% |
| Frontend | 13% | 80% |

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

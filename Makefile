# Makefile

.PHONY: up down build logs shell firestore-reset \
	check lint lint-backend lint-frontend lint-infra format audit \
	test test-backend test-frontend test-widgetbook test-goldens goldens-pull test-rules \
	coverage coverage-backend coverage-frontend \
	contracts-update \
	e2e e2e-up e2e-down e2e-logs e2e-seed test-e2e test-e2e-phone \
	e2e-native-up e2e-native-down \
	load test-load app-size app-size-pull perf-frames \
	mutation-backend mutation-frontend

# Coverage minimums; keep in sync with BACKEND_MIN_COVERAGE/FRONTEND_MIN_COVERAGE in .github/workflows/ci.yml.
BACKEND_MIN_COVERAGE ?= 95
FRONTEND_MIN_COVERAGE ?= 95

# Backend commands run in the dev container, which has the test tooling and reaches the emulator.
# SECRET_KEY is only for tests; the dev compose file doesn't set one.
BACKEND_RUN = docker compose run --rm -e SECRET_KEY=test-only-not-secret backend
# Same, with the E2E stub server mounted at /e2e so ruff checks it with the backend's settings (as CI does).
BACKEND_RUN_WITH_E2E = docker compose run --rm -e SECRET_KEY=test-only-not-secret -v ./e2e:/e2e backend

# Start the containers in the background
up:
	docker compose up -d

# Stop the containers
down:
	docker compose down

# Rebuild the containers (use after adding new uv packages)
build:
	docker compose up -d --build

# View logs (follow mode)
logs:
	docker compose logs -f

# Access the backend container shell
shell:
	docker compose exec backend bash

# Stop everything and wipe the local Firestore emulator data volume
firestore-reset:
	docker compose down -v

# --- Quality checks (what CI runs; see TESTING.md) ---

# Lint and test everything
check: lint test

lint: lint-backend lint-frontend lint-infra

lint-backend:
	$(BACKEND_RUN_WITH_E2E) sh -c "ruff check . /e2e && ruff format --check . /e2e && mypy . && bandit -q -c pyproject.toml -r . -x '*/tests.py,*/tests_*.py'"

lint-frontend:
	cd frontend && dart format --output=none --set-exit-if-changed lib test tool integration_test test_driver && flutter analyze lib test tool integration_test test_driver
	cd frontend/widgetbook && flutter analyze

# infra/ as CI's Terraform job checks it, with the same tool versions (needs Docker)
TERRAFORM = docker run --rm -v "$(CURDIR)/infra:/infra" -w /infra hashicorp/terraform:1.16.5
TRIVY = aquasec/trivy:0.75.0@sha256:af6acf9a6b85dfe389a1941505c0ce9efef52a4719635e1a962f022a3d855daa
lint-infra:
	$(TERRAFORM) fmt -check -diff -recursive
	$(TERRAFORM) init -backend=false -input=false >/dev/null && $(TERRAFORM) validate
	docker run --rm -v "$(CURDIR)/infra:/data" -w /data ghcr.io/terraform-linters/tflint:v0.64.0 --format compact
	docker run --rm -v "$(CURDIR)/infra:/infra:ro" $(TRIVY) config --quiet --exit-code 1 --severity HIGH,CRITICAL /infra

# Known vulnerabilities in the locked dependencies, as CI's dependency audit checks (needs uv and Docker)
audit:
	cd backend && uv export --frozen --all-groups --no-emit-project --format requirements-txt -o "$${TMPDIR:-/tmp}/is-it-open-requirements.txt" -q
	uvx pip-audit==2.10.1 -r "$${TMPDIR:-/tmp}/is-it-open-requirements.txt" --require-hashes --disable-pip --progress-spinner off
	docker run --rm -v "$(CURDIR):/src:ro" -w /src ghcr.io/google/osv-scanner:v2.6.0 scan source --verbosity error \
		-L frontend/pubspec.lock -L frontend/widgetbook/pubspec.lock -L backend/uv.lock \
		-L docker/firestore-emulator/rules-test/package-lock.json

# Apply formatting and autofixable lint fixes
format:
	$(BACKEND_RUN_WITH_E2E) sh -c 'ruff check --fix . /e2e && ruff format . /e2e'
	cd frontend && dart format lib test tool integration_test test_driver

# --- Tests ---

test: test-backend test-frontend test-widgetbook test-goldens test-rules

# Backend suite against the Firestore emulator (skips tests marked quarantine)
test-backend:
	$(BACKEND_RUN) pytest -m "not quarantine"

test-frontend:
	cd frontend && flutter test -x quarantine

test-widgetbook:
	cd frontend/widgetbook && flutter test -x quarantine -x golden

# Golden tests: compared on Linux only (skipped elsewhere). See "Visual regression" in TESTING.md
test-goldens:
	cd frontend/widgetbook && TZ=UTC flutter test --tags golden

# Firestore security rules against the emulator, which it starts (needs Node.js 22+). See "Infrastructure" in TESTING.md
test-rules:
	docker compose up -d --wait firestore
	cd docker/firestore-emulator/rules-test && npm ci --ignore-scripts --no-audit --no-fund && npm test

# Replace the goldens with the set the Goldens CI job regenerated (RUN=<id>, default: this branch's latest run)
goldens-pull:
	frontend/widgetbook/tool/pull_goldens.sh $(RUN)

# --- Coverage (fails below the minimums above) ---

coverage: coverage-backend coverage-frontend

coverage-backend:
	$(BACKEND_RUN) pytest -m "not quarantine" --cov --cov-report=term --cov-report=html --cov-fail-under=$(BACKEND_MIN_COVERAGE)
	@echo "HTML report: backend/htmlcov/index.html"

coverage-frontend:
	cd frontend && dart run tool/coverage.dart imports && flutter test --coverage -x quarantine && dart run tool/coverage.dart check --min=$(FRONTEND_MIN_COVERAGE)

# --- API contract (see contracts/README.md) ---

# Regenerate contracts/openapi.json after an intended API change
contracts-update:
	docker compose run --rm -e SECRET_KEY=test-only-not-secret -e UPDATE_CONTRACTS=1 backend pytest tests/contracts/test_openapi_snapshot.py

# --- E2E (see e2e/README.md) ---
# The journeys need Chrome and a matching chromedriver, on PATH or at CHROMEDRIVER=/path/to/chromedriver.

E2E_COMPOSE = docker compose -f docker-compose.e2e.yml

# Everything in one go, as CI does: start the stack, run the journeys in both layouts, tear it down
# (also when a journey fails)
e2e:
	$(MAKE) e2e-up
	status=0; \
	e2e/run-web.sh || status=$$?; \
	E2E_BROWSER_SIZE=390x844 e2e/run-web.sh || status=$$?; \
	$(MAKE) e2e-down; exit $$status

# Build and start the stack from scratch (empty emulator, then seeded), and wait until it's healthy
e2e-up:
	$(E2E_COMPOSE) up -d --build --force-recreate --wait

e2e-down:
	$(E2E_COMPOSE) down -v

e2e-logs:
	$(E2E_COMPOSE) logs -f

# Reset the seeded account (e2e-seeded / e2e-password) on a running stack, e.g. after poking at it by hand
e2e-seed:
	$(E2E_COMPOSE) run --rm seed

# The journeys in headless Chrome against a running stack: the desktop layout, or the phone one.
# Pass flutter drive arguments with ARGS, e.g. make test-e2e ARGS=--no-headless to watch.
test-e2e:
	e2e/run-web.sh $(ARGS)

test-e2e-phone:
	E2E_BROWSER_SIZE=390x844 e2e/run-web.sh $(ARGS)

# The same stack without Docker (uv, Node.js, Java 21+ and python3). Run the journeys against it with
# make test-e2e ARGS=--dart-define=E2E_STUB_URL=http://127.0.0.1:18090
e2e-native-up:
	e2e/start-native.sh

e2e-native-down:
	e2e/start-native.sh stop

# --- Performance (slow; runs nightly in CI; see "Performance" in TESTING.md) ---

# The API load test (perf/load.js) against the E2E stack, which it starts and stops. VUS, DURATION and
# PLACES override its defaults (20 users for 2m, 200 extra places), e.g. make load VUS=60 DURATION=30s
load:
	$(MAKE) e2e-up
	status=0; $(MAKE) test-load || status=$$?; $(MAKE) e2e-down; exit $$status

# The load test against a running E2E stack. Results land in perf/results/.
test-load:
	mkdir -p perf/results
	docker run --rm --network is-it-open-e2e_default --user "$$(id -u):$$(id -g)" \
		-v "$(CURDIR)/perf:/perf" -e BASE_URL=http://backend:8000/api -e SUMMARY_DIR=/perf/results \
		-e VUS -e DURATION -e PLACES grafana/k6:2.3.0 run --quiet /perf/load.js

# Frame timing of map pan/zoom, calendar scrolling and search typing (frontend/integration_test/perf_test.dart)
# against a running E2E stack (make e2e-up). It needs profile mode on a desktop: Linux, as CI runs it
# (macOS doesn't build with Xcode 26+, #45). PERF_DEVICE picks another device.
PERF_DEVICE ?= linux
perf-frames:
	cd frontend && flutter drive --profile -d $(PERF_DEVICE) --driver=test_driver/perf_driver.dart \
		--target=integration_test/perf_test.dart --dart-define=ENV=e2e

# Release build sizes against frontend/app_size.json. Locally the sizes are only indicative: the
# baseline is measured by CI, with the Flutter version pinned in perf.yml.
app-size:
	cd frontend && flutter build apk --release --analyze-size --target-platform android-arm64 && flutter build web --release
	cd frontend && dart run tool/app_size.dart check --analysis="$$(ls -t ~/.flutter-devtools/apk-code-size-analysis_*.json | head -1)"

# Replaces frontend/app_size.json with the sizes the App size CI job measured (RUN=<run id>, or the latest
# Performance or Nightly run on this branch), after an intended size change or a Flutter upgrade
app-size-pull:
	frontend/tool/pull_app_size.sh $(RUN)

# --- Mutation testing (slow; runs nightly in CI) ---

mutation-backend:
	$(BACKEND_RUN) sh -c 'mutmut run; mutmut results'

mutation-frontend:
	cd frontend && flutter test --coverage && dart pub global activate mutation_test 1.8.0 && dart pub global run mutation_test --exclude-strings -c coverage/lcov.info mutation_test.xml

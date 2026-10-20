# Makefile

.PHONY: up down build logs shell firestore-reset \
	check lint lint-backend lint-frontend format \
	test test-backend test-frontend test-widgetbook \
	coverage coverage-backend coverage-frontend \
	contracts-update \
	e2e e2e-up e2e-down e2e-logs e2e-seed test-e2e test-e2e-phone \
	e2e-native-up e2e-native-down \
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

lint: lint-backend lint-frontend

lint-backend:
	$(BACKEND_RUN_WITH_E2E) sh -c 'ruff check . /e2e && ruff format --check . /e2e && mypy .'

lint-frontend:
	cd frontend && dart format --output=none --set-exit-if-changed lib test tool integration_test test_driver && flutter analyze lib test tool integration_test test_driver
	cd frontend/widgetbook && flutter analyze

# Apply formatting and autofixable lint fixes
format:
	$(BACKEND_RUN_WITH_E2E) sh -c 'ruff check --fix . /e2e && ruff format . /e2e'
	cd frontend && dart format lib test tool integration_test test_driver

# --- Tests ---

test: test-backend test-frontend test-widgetbook

# Backend suite against the Firestore emulator (skips tests marked quarantine)
test-backend:
	$(BACKEND_RUN) pytest -m "not quarantine"

test-frontend:
	cd frontend && flutter test -x quarantine

test-widgetbook:
	cd frontend/widgetbook && flutter test -x quarantine

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

# --- Mutation testing (slow; runs nightly in CI) ---

mutation-backend:
	$(BACKEND_RUN) sh -c 'mutmut run; mutmut results'

mutation-frontend:
	cd frontend && flutter test --coverage && dart pub global activate mutation_test 1.8.0 && dart pub global run mutation_test --exclude-strings -c coverage/lcov.info mutation_test.xml

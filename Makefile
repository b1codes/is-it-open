# Makefile

.PHONY: up down build logs shell firestore-reset \
	check lint lint-backend lint-frontend format \
	test test-backend test-frontend test-widgetbook \
	coverage coverage-backend coverage-frontend \
	contracts-update \
	e2e-up e2e-down e2e-logs \
	mutation-backend mutation-frontend

# Coverage minimums; keep in sync with BACKEND_MIN_COVERAGE/FRONTEND_MIN_COVERAGE in .github/workflows/ci.yml.
BACKEND_MIN_COVERAGE ?= 95
FRONTEND_MIN_COVERAGE ?= 95

# Backend commands run in the dev container, which has the test tooling and reaches the emulator.
# SECRET_KEY is only for tests; the dev compose file doesn't set one.
BACKEND_RUN = docker compose run --rm -e SECRET_KEY=test-only-not-secret backend

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
	$(BACKEND_RUN) sh -c 'ruff check . && ruff format --check . && mypy .'

lint-frontend:
	cd frontend && dart format --output=none --set-exit-if-changed lib test tool && flutter analyze lib test tool
	cd frontend/widgetbook && flutter analyze

# Apply formatting and autofixable lint fixes
format:
	$(BACKEND_RUN) sh -c 'ruff check --fix . && ruff format .'
	cd frontend && dart format lib test tool

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

# --- E2E stack (see e2e/README.md) ---

E2E_COMPOSE = docker compose -f docker-compose.e2e.yml

# Build and start the stack from scratch (empty emulator, then seeded), and wait until it's healthy
e2e-up:
	$(E2E_COMPOSE) up -d --build --force-recreate --wait

e2e-down:
	$(E2E_COMPOSE) down -v

e2e-logs:
	$(E2E_COMPOSE) logs -f

# --- Mutation testing (slow; runs nightly in CI) ---

mutation-backend:
	$(BACKEND_RUN) sh -c 'mutmut run; mutmut results'

mutation-frontend:
	cd frontend && flutter test --coverage && dart pub global activate mutation_test 1.8.0 && dart pub global run mutation_test --exclude-strings -c coverage/lcov.info mutation_test.xml

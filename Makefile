# Makefile

.PHONY: up down build logs shell test firestore-reset

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

# Run the backend test suite against the Firestore emulator
test:
	docker compose run --rm backend python manage.py test

# Stop everything and wipe the local Firestore emulator data volume
firestore-reset:
	docker compose down -v

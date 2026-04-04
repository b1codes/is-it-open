# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

**Is It Open** is a mobile app (Flutter) for looking up business hours and availability. It uses a Django REST API backend with PostGIS spatial queries and integrates with the TomTom API for POI search and geocoding. Key features include place bookmarking, business hours tracking, iCal calendar sync, and interactive OpenStreetMap-based maps.

## Development Commands

All backend commands run through Docker. The backend is not intended to run directly on the host.

```bash
make up              # Start containers
make down            # Stop containers
make build           # Rebuild after adding uv packages
make logs            # Tail backend logs
make shell           # Bash shell into backend container
make migrate         # Apply migrations
make makemigrations  # Generate migrations after model changes
make superuser       # Create Django admin superuser
```

**Run backend tests** (inside container):
```bash
docker compose exec backend python manage.py test
docker compose exec backend python manage.py test tests.test_api   # single test file
```

**Flutter:**
```bash
cd frontend
flutter run                          # Run on connected device/simulator
flutter run -d <device-id>           # Target specific device
flutter test                         # Run all tests
flutter analyze                      # Lint check
```

## Backend Architecture

**Stack:** Django 5 + Django Ninja (FastAPI-style) + PostgreSQL/PostGIS

The API is defined in `backend/config/api.py` as a single `NinjaAPI` instance with three routers:
- `/api/auth/*` — public (login, register) — `apps/users/api.py`
- `/api/places/*` — protected — `apps/places/api.py`
- `/api/calendar/*` — protected — `apps/calendar/api.py`

Auth uses a custom token model (`apps/users/auth.py` — `GlobalAuth`) that checks `Authorization: Bearer <token>` headers.

**Key apps:**
- `apps/users` — Django `User` + `AuthToken` + `UserProfile` (home/work addresses)
- `apps/places` — `Place` (TomTom POI data with coordinates) + `SavedPlace` (user bookmark with custom icon/color/pin)
- `apps/hours` — `BusinessHours` model (day_of_week + open/close times, FK to Place)
- `apps/calendar` — iCal proxy endpoint that fetches remote calendar URLs server-side
- `services/` — `TomTomClient` for search, geocoding, and opening hours parsing

**GeoDjango:** PostGIS is used for spatial queries. GDAL/GEOS paths are auto-configured for macOS (Homebrew) in `settings.py` and for Linux via env vars.

**Config:** Uses `python-decouple` for all secrets/env. Copy `backend/sample.env` → `backend/.env` for local setup. SQLite is the default local DB (no PostGIS needed) unless `DATABASE_URL` is set.

## Frontend Architecture

**Stack:** Flutter + Dart + flutter_bloc (BLoC pattern)

Entry point: `frontend/lib/main.dart` — sets up `RepositoryProvider<ApiService>` and top-level BLoCs (`AuthBloc`, `ThemeCubit`, `PreferencesCubit`).

**State management pattern:** BLoC/Cubit. Each feature has its own bloc in `lib/bloc/`. UI dispatches events, blocs emit states, widgets rebuild via `BlocBuilder`/`BlocListener`.

**Key modules:**
- `lib/services/api_service.dart` — single Dio HTTP client; stores auth token in SharedPreferences; handles base URL selection per platform (Android emulator uses `10.0.2.2`, iOS/desktop uses `localhost`)
- `lib/models/` — `Place`, `User`, `SavedPlace`, `BusinessHours` (pure Dart data classes with `fromJson`/`toJson`)
- `lib/screens/` — `HomeScreen` (responsive shell), `SearchScreen`, `PlaceDetailScreen`, `MyPlacesScreen`, `CalendarScreen`, `MapScreen`
- `lib/components/` — reusable widgets
- `lib/utils/app_theme.dart` — Glassmorphism design tokens (gradients, blur, dark/light variants)

**Calendar integration:** `device_calendar` for native calendar access, `icalendar_parser` for parsing iCal feeds fetched via the backend `/calendar/proxy` endpoint.

## Environment Setup

Backend env vars (see `backend/sample.env`):
- `SECRET_KEY` — required
- `TOMTOM_API_KEY` — required for search features
- `DATABASE_URL` — defaults to SQLite; set to PostGIS URL for spatial queries
- `DEBUG` — default `False`

For local macOS development without Docker, GDAL/GEOS must be installed via Homebrew. The default paths (`/opt/homebrew/opt/gdal/...`) are already configured in `settings.py`.

# Is It Open

**Is It Open** is a full-stack application designed to help users determine business hours and availability for various places. It features a robust Django backend backed by Google Cloud Firestore and a responsive Flutter frontend for map-based interaction.

---

## 🛠 Tech Stack

### Backend
*   **Framework**: [Django](https://www.djangoproject.com/) + [Django Ninja](https://django-ninja.rest-framework.com/) (FastAPI-like syntax for Django)
*   **Database**: [Google Cloud Firestore](https://cloud.google.com/firestore) (geohash-indexed locations), run locally with the [Firestore emulator](https://firebase.google.com/docs/emulator-suite/connect_firestore)
*   **Dependency Management**: [uv](https://github.com/astral-sh/uv)
*   **Containerization**: [Docker](https://www.docker.com/) & [Docker Compose](https://docs.docker.com/compose/)
*   **Utilities**: `python-decouple` (Config), `gunicorn` (WSGI Server)

### Frontend
*   **Framework**: [Flutter](https://flutter.dev/) (Dart)
*   **State Management**: [Bloc](https://bloclibrary.dev/)
*   **Maps**: [flutter_map](https://pub.dev/packages/flutter_map) with [latlong2](https://pub.dev/packages/latlong2)
*   **Networking**: [Dio](https://pub.dev/packages/dio)
*   **Other Key Libraries**: `calendar_view`, `shared_preferences`, `geolocator`

### Architecture

```mermaid
graph TD
    User["User Device"] -->|Interacts| UI["Flutter Frontend"]
    
    subgraph "Docker Containerized Backend"
        API["Django Ninja API"]
        DB[("Firestore Emulator")]
    end
    
    UI -->|"REST Requests (Dio)"| API
    UI -->|"Tile Requests"| OSM["OpenStreetMap"]
    API -->|"Geohash Queries"| DB
```

---

## ✨ Features

*   **Modern UI**: Fully overhauled **Glassmorphism** design with vibrant gradient backgrounds and frosted glass elements.
*   **Navigation**: Centralized **Side Menu** for quick access to Map, Search, Saved Places, Profile, and Settings.
*   **Geospatial Search**: Find places and business hours based on location (geohash queries on Firestore).
*   **Map Integration**: Interactive maps using OpenStreetMap tiles.
*   **Theme Control**: Light/Dark mode toggles with system reference.

---

## 📋 Prerequisites

Before you begin, ensure you have the following installed:
*   [Docker Desktop](https://www.docker.com/products/docker-desktop)
*   [FVM](https://fvm.app/documentation/getting-started/installation) (`brew install fvm`), which installs the Flutter version pinned in `.fvmrc`
*   [Make](https://www.gnu.org/software/make/) (Standard on macOS/Linux)

---

## 🚀 Getting Started

### 1. Clone the Repository
```bash
git clone https://github.com/your-username/is-it-open.git
cd is-it-open
```

### 2. Environment Setup
Create a `.env` file in the `backend/` directory based on the sample:
```bash
cp backend/sample.env backend/.env
```
*Update the `.env` file with your specific configuration if necessary.*

### 3. Start the Backend (Docker)
We use `make` commands to simplify Docker interactions.
```bash
make up
```
This will:
1.  Build the backend and Firestore emulator containers.
2.  Start the Firestore emulator (data persists in a Docker volume between restarts).
3.  Start the Django development server on port `8001`.

Firestore is schemaless, so there are no migrations to run. Browse local data in the
Emulator UI at <http://localhost:4000/firestore>. See [`docker/firestore-emulator/README.md`](docker/firestore-emulator/README.md) for details.

**Run Tests:**
```bash
make test-backend   # backend only
make check          # every lint and test suite, as CI runs them
```
Tests use a separate emulator project, so they never touch your local data. See [`TESTING.md`](TESTING.md) for every suite, coverage minimums, and the CI setup.

### 4. Run the Frontend (Flutter)
Open a new terminal tab, install the pinned Flutter SDK, and navigate to the frontend directory:
```bash
fvm install
cd frontend
fvm flutter pub get
fvm flutter run
```
The `make` targets use `fvm flutter` too when FVM is installed, and VS Code uses the pinned SDK through `.vscode/settings.json`.

### 5. Browse the Component Catalog (Widgetbook)
Every component and screen has [Widgetbook](https://www.widgetbook.io/) use cases backed by mock data, so no backend is needed:
```bash
cd frontend/widgetbook
fvm flutter pub get
fvm flutter run -d chrome
```
See [`frontend/widgetbook/README.md`](frontend/widgetbook/README.md) for adding use cases.

---

## 📂 Project Structure

```
is-it-open/
├── backend/                # Django Project
│   ├── apps/               # Django Apps (Feature modules)
│   │   ├── users/          # User management & Auth (Firestore repository)
│   │   ├── places/         # Places, hours & bookmarks (Firestore repository)
│   │   └── calendar/       # iCal proxy
│   ├── services/           # TomTom client, Firestore client, geohash helpers
│   ├── config/             # Project settings (settings.py, urls.py)
│   ├── Dockerfile          # Backend container definition
│   └── pyproject.toml      # uv dependencies
│
├── frontend/               # Flutter Project
│   ├── lib/                # Dart source code
│   │   ├── components/     # Reusable UI widgets
│   │   ├── screens/        # App pages (Map, Me, etc.)
│   │   └── main.dart       # Entry point
│   ├── widgetbook/         # Widgetbook component catalog
│   └── pubspec.yaml        # Flutter dependencies
│
├── docker/
│   └── firestore-emulator/ # Local Firestore emulator + Emulator UI container
│
├── docker-compose.yml      # Service orchestration
└── Makefile                # Shortcut commands
```

---

## ⚡ Key Commands (Makefile)

Use these commands from the root directory to manage the project:

| Command | Description |
| :--- | :--- |
| `make up` | Start all services in the background (detached mode) |
| `make down` | Stop and remove all containers |
| `make build` | Rebuild the containers (run after adding new uv packages) |
| `make logs` | View backend logs in follow mode |
| `make shell` | Access the backend container's shell (`bash`) |
| `make test` | Run the backend, frontend, and Widgetbook test suites (see [`TESTING.md`](TESTING.md)) |
| `make check` | Run every lint and test suite, as CI does |
| `make firestore-reset` | Stop everything and wipe local Firestore emulator data |

---
#!/usr/bin/env bash
# Starts the E2E stack without Docker, for machines that have none (GitHub's macOS runners, which
# run the iOS simulator journeys). Same services and settings as docker-compose.e2e.yml, on the same
# host ports, except the emulator, which uses 18080 so it can't clash with the dev one on 8080:
#
#   firestore  127.0.0.1:18080   empty on every start
#   stub       127.0.0.1:18090   e2e/stub/server.py
#   backend    127.0.0.1:18000   gunicorn, after `manage.py seed_e2e`
#
# The backend reaches the stub at 127.0.0.1 here, not at http://stub:8090, so run the journeys with
# --dart-define=E2E_STUB_URL=http://127.0.0.1:18090 (see e2e/README.md).
#
# Needs uv, Node.js (npx), Java 21+ and python3. Logs go to e2e/.native/.
#
#   e2e/start-native.sh        # start and wait until healthy
#   e2e/start-native.sh stop
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
state="${root}/e2e/.native"
firebase_tools="firebase-tools@15.31.0"  # as docker/firestore-emulator/Dockerfile

stop() {
  pkill -f "emulators:start --only firestore --project demo-is-it-open-e2e" 2> /dev/null || true
  pkill -f "cloud-firestore-emulator.*--port 18080" 2> /dev/null || true
  pkill -f "${root}/e2e/stub/server.py" 2> /dev/null || true
  pkill -f "gunicorn config.asgi:application.*127.0.0.1:18000" 2> /dev/null || true
}

wait_for() {
  local name=$1 url=$2
  for _ in $(seq 120); do
    curl -fsS "${url}" > /dev/null 2>&1 && return 0
    sleep 1
  done
  echo "${name} didn't start; see e2e/.native/${name}.log" >&2
  exit 1
}

if [ "${1:-}" = "stop" ]; then
  stop
  exit 0
fi

stop
mkdir -p "${state}"

cat > "${state}/firebase.json" << EOF
{
  "firestore": { "rules": "${root}/docker/firestore-emulator/firestore.rules" },
  "emulators": {
    "firestore": { "host": "127.0.0.1", "port": 18080 },
    "ui": { "enabled": false }
  }
}
EOF
npx -y "${firebase_tools}" emulators:start --only firestore --project demo-is-it-open-e2e \
  --config "${state}/firebase.json" > "${state}/firestore.log" 2>&1 &

FIXTURES_DIR="${root}/contracts/tomtom/fixtures" PORT=18090 \
  python3 "${root}/e2e/stub/server.py" > "${state}/stub.log" 2>&1 &

cd "${root}/backend"
# Its own environment, so a developer's backend/.venv keeps its dev dependencies. Python as in
# backend/Dockerfile.
export UV_PROJECT_ENVIRONMENT="${state}/venv" UV_PYTHON=3.11
# On macOS, a forked gunicorn worker that reads the system proxy settings (as requests does on its
# first call out) is killed by the Objective-C runtime. Nothing here goes through a proxy anyway.
export OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES NO_PROXY='*'
uv sync --frozen --no-dev --quiet
set -a
# shellcheck source=e2e/backend.env
. "${root}/e2e/backend.env"
set +a
export FIRESTORE_EMULATOR_HOST=127.0.0.1:18080
export TOMTOM_BASE_URL=http://127.0.0.1:18090/search/2
# The calendar proxy only fetches from public hosts, except the stub's iCal feed.
export SAFE_FETCH_PRIVATE_HOSTS=127.0.0.1

wait_for firestore http://127.0.0.1:18080/
wait_for stub http://127.0.0.1:18090/health
"${state}/venv/bin/python" manage.py seed_e2e > "${state}/backend.log" 2>&1
"${state}/venv/bin/gunicorn" config.asgi:application -k uvicorn.workers.UvicornWorker \
  --bind 127.0.0.1:18000 --workers 2 --access-logfile - >> "${state}/backend.log" 2>&1 &
wait_for backend http://127.0.0.1:18000/api/openapi.json

echo "E2E stack is up (logs in e2e/.native/). Stop it with: e2e/start-native.sh stop"

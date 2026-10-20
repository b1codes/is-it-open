#!/usr/bin/env bash
# Runs the E2E journeys (frontend/integration_test) in headless Chrome against the E2E stack.
#
#   make e2e-up && make test-e2e
#
# Needs Chrome and a matching chromedriver: on PATH, or CHROMEDRIVER=/path/to/chromedriver
# (`npx @puppeteer/browsers install chromedriver@<your Chrome version>` fetches one).
# E2E_BROWSER_SIZE picks the layout: 1600x1024 (desktop, the default) or 390x844 (phone).
# Extra arguments go to `flutter drive`, e.g. --no-headless to watch.
set -euo pipefail

cd "$(dirname "$0")/../frontend"

port="${CHROMEDRIVER_PORT:-4444}"
size="${E2E_BROWSER_SIZE:-1600x1024}"

if ! curl -fsS http://127.0.0.1:18000/api/openapi.json > /dev/null 2>&1; then
  echo "The E2E stack isn't running. Start it with: make e2e-up" >&2
  exit 1
fi

if ! curl -fsS "http://127.0.0.1:${port}/status" > /dev/null 2>&1; then
  "${CHROMEDRIVER:-chromedriver}" --port="${port}" > build/chromedriver.log 2>&1 &
  driver_pid=$!
  trap 'kill "${driver_pid}" 2> /dev/null || true' EXIT
  for _ in $(seq 50); do
    curl -fsS "http://127.0.0.1:${port}/status" > /dev/null 2>&1 && break
    sleep 0.2
  done
fi

rm -rf build/e2e-screenshots
flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/app_test.dart \
  -d web-server --browser-name=chrome --headless \
  --browser-dimension="${size}" \
  --driver-port="${port}" \
  --dart-define=ENV=e2e \
  "$@"

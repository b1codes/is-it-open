#!/usr/bin/env bash
# Runs the E2E journeys (frontend/integration_test) in headless Chrome against the E2E stack.
#
#   make e2e-up && make test-e2e
#
# Needs Chrome. The chromedriver is CHROMEDRIVER=/path/to/chromedriver if set, else one on PATH that
# matches your Chrome, else one downloaded for it into frontend/build/chromedriver (needs npx).
# Chrome updates itself, so a chromedriver fetched once goes stale.
# E2E_BROWSER_SIZE picks the layout: 1600x1024 (desktop, the default) or 390x844 (phone).
# Extra arguments go to `flutter drive`, e.g. --no-headless to watch.
set -euo pipefail

cd "$(dirname "$0")/../frontend"

port="${CHROMEDRIVER_PORT:-4444}"
size="${E2E_BROWSER_SIZE:-1600x1024}"
mkdir -p build

if ! curl -fsS http://127.0.0.1:18000/api/openapi.json > /dev/null 2>&1; then
  echo "The E2E stack isn't running. Start it with: make e2e-up" >&2
  exit 1
fi

chrome_version() {
  local chrome
  for chrome in "${CHROME_EXECUTABLE:-}" "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
    google-chrome google-chrome-stable chromium; do
    if [ -n "${chrome}" ] && command -v "${chrome}" > /dev/null 2>&1; then
      "${chrome}" --version | grep -oE '[0-9]+(\.[0-9]+){3}' || true
      return
    fi
  done
}

downloaded_chromedriver() {
  find build/chromedriver -type f -name chromedriver -path "*$1*" 2> /dev/null | head -n 1
}

find_chromedriver() {
  if [ -n "${CHROMEDRIVER:-}" ]; then
    echo "${CHROMEDRIVER}"
    return
  fi
  local version major found
  version="$(chrome_version)"
  if [ -z "${version}" ]; then
    echo chromedriver # Chrome not found: let chromedriver report it.
    return
  fi
  major="${version%%.*}"
  if command -v chromedriver > /dev/null 2>&1 && chromedriver --version | grep -q " ${major}\."; then
    echo chromedriver
    return
  fi
  found="$(downloaded_chromedriver "${version}")"
  if [ -z "${found}" ]; then
    echo "Downloading chromedriver ${version} to match your Chrome..." >&2
    npx -y @puppeteer/browsers install "chromedriver@${version}" --path build/chromedriver >&2 ||
      npx -y @puppeteer/browsers install "chromedriver@${major}" --path build/chromedriver >&2
    found="$(downloaded_chromedriver "${major}.")"
  fi
  echo "${found:-chromedriver}"
}

if ! curl -fsS "http://127.0.0.1:${port}/status" > /dev/null 2>&1; then
  "$(find_chromedriver)" --port="${port}" > build/chromedriver.log 2>&1 &
  driver_pid=$!
  trap 'kill "${driver_pid}" 2> /dev/null || true' EXIT
  for _ in $(seq 50); do
    curl -fsS "http://127.0.0.1:${port}/status" > /dev/null 2>&1 && break
    sleep 0.2
  done
  curl -fsS "http://127.0.0.1:${port}/status" > /dev/null 2>&1 || {
    echo "chromedriver didn't start; see frontend/build/chromedriver.log" >&2
    exit 1
  }
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

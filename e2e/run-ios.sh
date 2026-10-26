#!/usr/bin/env bash
# The E2E journeys on an iOS simulator, as the nightly iOS job runs them (see e2e/README.md). Run
# from frontend/, with the E2E stack up; arguments go to `flutter test`:
#
#   UDID=<simulator udid> ../e2e/run-ios.sh --dart-define=ENV=e2e --dart-define=MONKEY=true
#
# After the build, `flutter test` launches the app and waits, with no timeout, for it to print its
# VM service address on the simulator's log. Now and then on CI that never comes (#63): the app
# normally attaches about 40 s after the build, but some runs sat there until the job timed out.
# So this boots the simulator and waits until it has finished booting, and if no test has started
# ATTACH_TIMEOUT seconds after the build, it stops that attempt (`flutter test` and everything it
# started, and the app), reboots the simulator and tries again, up to ATTEMPTS times. The output
# of every attempt, and the simulator's log of the app for each one that didn't attach, are kept in
# build/ios-e2e/.
set -uo pipefail

udid="${UDID:?set UDID}"
attach_timeout="${ATTACH_TIMEOUT:-240}"
attempts="${ATTEMPTS:-3}"
out=build/ios-e2e
mkdir -p "${out}"

# Runs a command, killing it after $1 seconds (macOS has no timeout(1)).
with_timeout() {
  perl -e 'alarm shift; exec @ARGV or die "exec: $!"' "$@"
}

# `simctl boot` returns before the device has finished booting; bootstatus waits for it. A boot
# that hangs is shut down and tried again.
boot() {
  for _ in 1 2 3; do
    xcrun simctl boot "${udid}" 2> /dev/null
    if with_timeout 300 xcrun simctl bootstatus "${udid}" -b > /dev/null; then
      return 0
    fi
    echo "::warning::The simulator didn't finish booting in 5 minutes; restarting it"
    xcrun simctl shutdown "${udid}" 2> /dev/null
  done
  echo "::error::The simulator didn't boot"
  return 1
}

# What the simulator says about the app, for a launch that didn't attach: whether it's running, and
# its log (the VM service line flutter waits for, or a crash).
diagnose() {
  {
    echo "--- launchctl"
    xcrun simctl spawn "${udid}" launchctl list | grep -i isitopen || echo "not running"
    echo "--- log"
    xcrun simctl spawn "${udid}" log show --last 15m --style compact --predicate 'process == "Runner"'
  } > "$1" 2>&1
  grep -iE 'not running|VM Service|Observatory|crash' "$1" | tail -n 5
}

# Stops the attempt: the process group `flutter test` leads (the tool, its log readers, DDS), and
# the app, so a later attempt doesn't find any of them on the simulator.
stop() {
  kill -TERM -- "-$1" 2> /dev/null
  sleep 5
  kill -KILL -- "-$1" 2> /dev/null
  xcrun simctl terminate "${udid}" com.brandonlc.isitopen 2> /dev/null
}

# Whether the log shows the build done, and a test (or setUpAll) started after it.
is_built() { grep -q '^Xcode build done' "$1"; }
is_attached() { sed -n '/^Xcode build done/,$p' "$1" | grep -qE '^[0-9]+:[0-9]{2} \+[0-9]+'; }

for attempt in $(seq "${attempts}"); do
  boot || exit 1
  log="${out}/attempt-${attempt}.log"
  echo "::group::flutter test, attempt ${attempt} of ${attempts}"
  # Job control gives `flutter test` a process group of its own, so stop() can kill all of it.
  set -m
  flutter test integration_test/app_test.dart -r expanded -d "${udid}" "$@" > "${log}" 2>&1 &
  pid=$!
  set +m
  tail -n +1 -f "${log}" &
  tail_pid=$!
  disown "${tail_pid}"

  # Wait for the build, then for the app to attach, or for `flutter test` to exit.
  built=
  while kill -0 "${pid}" 2> /dev/null && ! is_attached "${log}"; do
    if [ -z "${built}" ] && is_built "${log}"; then
      built=${SECONDS}
    elif [ -n "${built}" ] && (( SECONDS - built > attach_timeout )); then
      break
    fi
    sleep 5
  done

  if is_attached "${log}" || ! is_built "${log}"; then
    # It attached, or it stopped before the app was built (a build error): its exit status is
    # the result.
    wait "${pid}"
    status=$?
    sleep 1
    kill "${tail_pid}" 2> /dev/null
    echo "::endgroup::"
    exit "${status}"
  fi

  kill "${tail_pid}" 2> /dev/null
  echo "::endgroup::"
  diagnose "${out}/attempt-${attempt}-simulator.log"
  if kill -0 "${pid}" 2> /dev/null; then
    echo "::warning::Attempt ${attempt} of ${attempts}: the app didn't attach within ${attach_timeout} s of the build (#63)"
  else
    echo "::warning::Attempt ${attempt} of ${attempts}: flutter test stopped before the app attached (#63)"
  fi
  disown "${pid}"
  stop "${pid}"
  xcrun simctl shutdown "${udid}" 2> /dev/null
done

echo "::error::The app didn't attach to flutter test on the simulator in ${attempts} attempts (#63)"
exit 1

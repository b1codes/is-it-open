#!/usr/bin/env bash
# Android's own monkey (adb shell monkey) on a running emulator (see TESTING.md, "Monkey testing").
# Run from frontend/, with the E2E stack's ports reversed into the emulator:
#
#   SEED=123 MONKEY_EVENTS=5000 ../e2e/android-monkey.sh
#
# It installs a debug build of the app and sends random events through the OS, from a fresh install
# (signed out), so it also catches native crashes and ANRs. A debug build logs every Flutter error to
# logcat; any that isn't a known Flutter bug (knownFlutterBugs in
# integration_test/helpers/monkey.dart) fails the run too. Logs land in build/android-monkey/.
# (The app's own monkey runs after the journeys, in integration_test/app_test.dart.)
set -uo pipefail

seed="${SEED:?set SEED}"
events="${MONKEY_EVENTS:-5000}"
package=com.example.frontend
out=build/android-monkey
mkdir -p "${out}"
status=0

echo "::group::adb shell monkey (seed ${seed}, ${events} events)"
flutter build apk --debug --dart-define=ENV=e2e || exit 1
adb install -r build/app/outputs/flutter-apk/app-debug.apk || exit 1
adb logcat -c
# A debug build takes a while to start on the emulator; touches sent before its window is up count
# as an ANR. Start it, wait until it's displayed, and give it a moment before the monkey takes over.
adb shell am start -W -n "${package}/.MainActivity" > /dev/null
sleep 15
# No system keys or app switches: home and recents would leave the app, and the monkey would spend
# the run outside it.
adb shell monkey -p "${package}" -s "${seed}" --throttle 100 \
  --pct-syskeys 0 --pct-appswitch 0 -v "${events}" > "${out}/adb-monkey.log" 2>&1
adb logcat -d > "${out}/logcat.txt"
tail -n 5 "${out}/adb-monkey.log"
if grep -qE '// CRASH|// NOT RESPONDING|Monkey aborted' "${out}/adb-monkey.log"; then
  echo "::error::adb monkey: the app crashed or stopped responding (seed ${seed}); see ${out}/adb-monkey.log"
  status=1
fi
# Flutter errors, from the debug build's log, minus the known Flutter bugs.
python3 - "${out}/logcat.txt" <<'PY' || status=1
import sys

# Matched with whitespace collapsed: the log wraps long messages.
# Keep in step with knownFlutterBugs in integration_test/helpers/monkey.dart.
known = [
    "'_hold == null'",
]
lines = [l.split(": ", 1)[-1] for l in open(sys.argv[1], errors="replace") if " flutter " in l]
errors = []
for i, line in enumerate(lines):
    if "EXCEPTION CAUGHT BY" in line:
        block = "\n".join(lines[i : i + 12])
        if not any(k in " ".join(block.split()) for k in known):
            errors.append(block)
for block in errors:
    print(block, end="\n\n")
if errors:
    print(f"::error::adb monkey: {len(errors)} Flutter error(s) in logcat")
    sys.exit(1)
PY
echo "::endgroup::"

exit "${status}"

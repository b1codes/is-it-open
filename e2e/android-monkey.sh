#!/usr/bin/env bash
# The monkey tests on a running Android emulator, against the E2E stack (see TESTING.md, "Monkey
# testing"). Run from frontend/, with the stack's ports reversed into the emulator:
#
#   SEED=123 MONKEY_STEPS=800 MONKEY_EVENTS=5000 ../e2e/android-monkey.sh
#
# 1. The app's own monkey (integration_test/monkey_test.dart), signed in.
# 2. Android's monkey (adb shell monkey) on a debug build of the app, from a fresh install (signed
#    out). It sends real touch events through the OS, so it also catches native crashes and ANRs.
#    A debug build logs every Flutter error to logcat; any that isn't a known Flutter bug (see
#    knownFlutterBugs in integration_test/helpers/monkey.dart) fails the run too.
#
# Both run even if the first fails. Logs land in build/android-monkey/.
set -uo pipefail

seed="${SEED:?set SEED}"
steps="${MONKEY_STEPS:-800}"
events="${MONKEY_EVENTS:-5000}"
package=com.example.frontend
out=build/android-monkey
mkdir -p "${out}"
status=0

echo "::group::App monkey (seed ${seed}, ${steps} steps)"
flutter test integration_test/monkey_test.dart -r expanded -d emulator-5554 \
  --dart-define=ENV=e2e --dart-define=SEED="${seed}" --dart-define=MONKEY_STEPS="${steps}" || status=1
echo "::endgroup::"

echo "::group::adb shell monkey (seed ${seed}, ${events} events)"
flutter build apk --debug --dart-define=ENV=e2e || exit 1
adb install -r build/app/outputs/flutter-apk/app-debug.apk || exit 1
adb logcat -c
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
known = [
    "'_hold == null'",
    "'manifest.fromHero == newManifest.toHero'",
    "'manifest.toHero == newManifest.fromHero'",
    "_handleContextMenuOnScroll",
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

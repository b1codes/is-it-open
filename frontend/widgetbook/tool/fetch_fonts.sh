#!/usr/bin/env bash
# Downloads the Google Fonts the app uses into assets/google_fonts/, so the
# golden tests (and the catalog) render real Montserrat and Open Sans without
# network access. google_fonts finds them there by file name.
#
# The hashes are the ones google_fonts (see pubspec.lock) fetches at runtime,
# from lib/src/google_fonts_parts/part_{m,o}.dart, so the bundled files are
# byte-for-byte what a device downloads. Add a line when the app starts using a
# new weight: the golden tests fail with "allowRuntimeFetching is false but
# font <name> was not found" until it's bundled. Re-run after a google_fonts
# upgrade that changes these hashes, then regenerate the goldens.
set -euo pipefail

cd "$(dirname "$0")/.."
out=assets/google_fonts
mkdir -p "$out"

fonts=(
  "Montserrat-SemiBold ff847b201647579bb6cd0f46de344b5731f9e4932308842b7b4dce64fc27c0ef"
  "Montserrat-Bold 6909027d44d53e9a64ea940b0a7aea9d04187d1bb8ab17a178d99a46bf9ef320"
  "OpenSans-Regular 5af20f022c70222f0e960f45a033366eb2582c982031a715f9cafc05acbc51a5"
  "OpenSans-Medium 5a420b44a9efa533fe670589230b4a68b40ff2c7a414f6c0323b160b5d29e264"
  "OpenSans-SemiBold bf8d1e8b98d005159eb2c42793291812bebda2f0f17500290b100cb7810583fd"
)

for entry in "${fonts[@]}"; do
  read -r name hash <<<"$entry"
  curl -fsSL --retry 3 -o "$out/$name.ttf" "https://fonts.gstatic.com/s/a/$hash.ttf"
  echo "$hash  $out/$name.ttf" | shasum -a 256 -c -
done

for family in montserrat opensans; do
  curl -fsSL --retry 3 -o "$out/OFL-$family.txt" \
    "https://raw.githubusercontent.com/google/fonts/main/ofl/$family/OFL.txt"
done

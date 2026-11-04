#!/usr/bin/env bash
# Replaces test/goldens/ with the set the Goldens CI job regenerated (the
# goldens-updated artifact), so an intended UI change can be reviewed and
# committed. The goldens are only valid when rendered by that job, so they
# aren't regenerated locally. See "Visual regression" in TESTING.md.
#
# Usage: tool/pull_goldens.sh [run-id]   (default: the latest CI run on this branch)
set -euo pipefail

cd "$(dirname "$0")/.."

run=${1:-}
if [ -z "$run" ]; then
  branch=$(git branch --show-current)
  run=$(gh run list --branch "$branch" --workflow ci.yml --limit 1 --json databaseId --jq '.[0].databaseId')
  if [ -z "$run" ]; then
    echo "No CI run found for branch $branch." >&2
    exit 1
  fi
fi

sha=$(gh run view "$run" --json headSha --jq .headSha)
if [ "$sha" != "$(git rev-parse HEAD)" ]; then
  echo "Note: CI run $run rendered ${sha:0:7}, not your HEAD ($(git rev-parse --short HEAD))." >&2
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
if ! gh run download "$run" --name goldens-updated --dir "$tmp"; then
  echo "CI run $run has no goldens-updated artifact: its goldens matched, or it hasn't finished." >&2
  exit 1
fi

rm -rf test/goldens
mkdir -p test/goldens
cp -R "$tmp"/. test/goldens/
echo "Goldens from CI run $run (${sha:0:7}):"
git status --short --untracked-files=all -- test/goldens | awk '{print $1}' | sort | uniq -c
echo "Review the changed images (git diff, or your Git client's image diff), then commit test/goldens/."

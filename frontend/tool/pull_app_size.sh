#!/usr/bin/env bash
# Replaces app_size.json, the app size baseline, with what the App size CI job measured (the
# app-size artifact), after an intended size change or a Flutter upgrade. Sizes are only
# comparable when measured by that job, so the baseline isn't measured locally. See "Performance"
# in TESTING.md.
#
# Usage: tool/pull_app_size.sh [run-id]   (default: the latest Performance or Nightly run on this branch)
set -euo pipefail

cd "$(dirname "$0")/.."

run=${1:-}
if [ -z "$run" ]; then
  branch=$(git branch --show-current)
  run=$( { gh run list --branch "$branch" --workflow perf.yml --limit 1 --json databaseId,createdAt
           gh run list --branch "$branch" --workflow nightly.yml --limit 1 --json databaseId,createdAt
         } | jq -rs 'add | sort_by(.createdAt) | last | .databaseId // empty')
  if [ -z "$run" ]; then
    echo "No Performance or Nightly run found for branch $branch." >&2
    exit 1
  fi
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
if ! gh run download "$run" --name app-size --dir "$tmp"; then
  echo "Run $run has no app-size artifact: the job didn't get to measure, or the run hasn't finished." >&2
  exit 1
fi

cp "$tmp/measured.json" app_size.json
echo "app_size.json from run $run:"
git --no-pager diff --stat -- app_size.json
echo "Check the sizes in the run's summary, then commit frontend/app_size.json."

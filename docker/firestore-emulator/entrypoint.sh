#!/bin/sh
# Starts the Firestore emulator, restoring the last export if one exists and exporting
# back when the container is stopped. The Firebase CLI replaces the export directory
# wholesale, so it lives in a subdirectory of the /data volume rather than at its root.
set -e

EXPORT_DIR=/data/export

IMPORT_ARGS=""
if [ -f "${EXPORT_DIR}/firebase-export-metadata.json" ]; then
  IMPORT_ARGS="--import=${EXPORT_DIR}"
fi

exec firebase emulators:start \
  --only firestore \
  --project "${FIRESTORE_PROJECT_ID}" \
  ${IMPORT_ARGS} \
  --export-on-exit="${EXPORT_DIR}"

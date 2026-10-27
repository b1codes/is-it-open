# docker/firestore-emulator/Dockerfile
# Local Google Cloud Firestore emulator (plus the Emulator UI) via the Firebase CLI.
FROM node:26.12.1-trixie-slim

# The Firebase emulators need Java 21+; curl backs the healthcheck.
RUN apt-get update && apt-get install -y --no-install-recommends \
    openjdk-21-jre-headless curl \
    && rm -rf /var/lib/apt/lists/*

ARG FIREBASE_TOOLS_VERSION=15.31.0
RUN npm install -g firebase-tools@${FIREBASE_TOOLS_VERSION} && npm cache clean --force

ENV NO_UPDATE_NOTIFIER=1 \
    FIRESTORE_PROJECT_ID=demo-is-it-open

WORKDIR /firebase
COPY firebase.json firestore.rules ./
COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh

# Persisted emulator data (imported on start, exported on shutdown).
RUN mkdir -p /data && chown node:node /data /firebase

USER node

# Download the emulator jars at build time so the container starts offline.
RUN firebase setup:emulators:firestore && firebase setup:emulators:ui

# 8080: Firestore API, 4000: Emulator UI, 9150: Firestore websocket used by the UI
EXPOSE 8080 4000 9150

HEALTHCHECK --interval=5s --timeout=3s --start-period=20s --retries=12 \
    CMD curl -fsS http://localhost:8080/ || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

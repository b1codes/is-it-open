import os
from urllib.parse import quote

import requests
from django.conf import settings
from google.cloud import firestore

_clients = {}


def get_client() -> firestore.Client:
    """Return a Firestore client for the configured project, cached per project/database."""
    if settings.FIRESTORE_EMULATOR_HOST:
        # The client library only reads the emulator host from the process environment.
        os.environ["FIRESTORE_EMULATOR_HOST"] = settings.FIRESTORE_EMULATOR_HOST

    key = (settings.GOOGLE_CLOUD_PROJECT, settings.FIRESTORE_DATABASE)
    if key not in _clients:
        _clients[key] = firestore.Client(project=key[0], database=key[1])
    return _clients[key]


def doc_id(key: str) -> str:
    """Encode an arbitrary natural key (e.g. a TomTom ID or Auth0 sub) as a valid document ID."""
    encoded = quote(key, safe="|@:+")
    if encoded in (".", ".."):
        encoded = encoded.replace(".", "%2E")
    return encoded


def allocate_id(transaction, name: str) -> int:
    """
    Allocate the next sequential integer ID for `name` inside `transaction`.

    Firestore document IDs are strings, but the API (and the Flutter app) expose integer IDs,
    so we keep a counter document per entity type. Must be called before any transaction writes.
    """
    ref = get_client().collection("counters").document(name)
    snapshot = ref.get(transaction=transaction)
    value = (snapshot.get("value") if snapshot.exists else 0) + 1
    transaction.set(ref, {"value": value})
    return value


def clear_emulator():
    """Delete every document in the configured project. Only works against the emulator."""
    host = settings.FIRESTORE_EMULATOR_HOST
    if not host:
        raise RuntimeError("clear_emulator() refuses to run without FIRESTORE_EMULATOR_HOST")
    url = (
        f"http://{host}/emulator/v1/projects/{settings.GOOGLE_CLOUD_PROJECT}"
        f"/databases/{settings.FIRESTORE_DATABASE}/documents"
    )
    requests.delete(url, timeout=10).raise_for_status()

import hashlib
import os
import random
import re
import threading
import time
from urllib.parse import quote

import requests
from django.conf import settings
from google.api_core import exceptions as api_exceptions
from google.cloud import firestore
from google.cloud.firestore_v1 import _helpers as firestore_helpers

_clients = {}

COUNTERS = "counters"

# Largest integer a JavaScript client (and Dart on the web) can represent exactly.
MAX_SAFE_ID = 2**53 - 1

# How many IDs a process reserves from a counter document in one write.
ID_BLOCK_SIZE = 50

# Retry reservations that fail on contention or transient errors. A retry after an ambiguous
# failure can only leave a gap in the IDs, never hand one out twice.
_RESERVE_ATTEMPTS = 6
_RESERVE_BACKOFF_SECONDS = 0.05
_RESERVE_RETRYABLE = (
    api_exceptions.Aborted,
    api_exceptions.DeadlineExceeded,
    api_exceptions.ResourceExhausted,
    api_exceptions.ServiceUnavailable,
)

# Firestore document ID limit, in UTF-8 bytes.
_MAX_DOC_ID_BYTES = 1500

# Firestore reserves IDs matching this pattern.
_RESERVED_DOC_ID = re.compile(r"__.*__", re.DOTALL)

# Prefix for hashed (overlong) keys. quote() only ever emits '%' followed by two uppercase hex
# digits, so no ordinary encoded key can start with '%s'.
_HASHED_PREFIX = "%sha256:"


def get_client() -> firestore.Client:
    """Return a Firestore client for the configured project, cached per project/database."""
    if settings.FIRESTORE_EMULATOR_HOST:
        # The client library only reads the emulator host from the process environment.
        os.environ["FIRESTORE_EMULATOR_HOST"] = settings.FIRESTORE_EMULATOR_HOST

    key = (settings.GOOGLE_CLOUD_PROJECT, settings.FIRESTORE_DATABASE)
    if key not in _clients:
        _clients[key] = firestore.Client(project=key[0], database=key[1])
    return _clients[key]


class InvalidDocumentKey(ValueError):
    """The natural key can't be stored as a document ID (it is empty or not valid Unicode)."""


def doc_id(key: str) -> str:
    """
    Encode an arbitrary natural key (e.g. a TomTom ID or Auth0 sub) as a valid document ID.

    The encoding is deterministic and injective: ordinary keys are percent-encoded (so the result
    never contains '/'), and the extra escapes below only use sequences quote() never produces
    ('%2E', '%5F'), so unquote() recovers the original key. Keys whose encoding is too long for
    Firestore are hashed under a prefix no encoded key can start with.

    Raises InvalidDocumentKey for keys that can't be stored at all.
    """
    if not isinstance(key, str) or not key:
        raise InvalidDocumentKey("Document keys must be non-empty strings")
    try:
        encoded = quote(key, safe="|@:+")
    except UnicodeEncodeError as e:
        raise InvalidDocumentKey("Document keys must be valid Unicode") from e

    if encoded in (".", ".."):
        encoded = encoded.replace(".", "%2E")
    elif _RESERVED_DOC_ID.fullmatch(encoded):
        # '_' is never escaped by quote(), so '%5F' can only come from here.
        encoded = "%5F" + encoded[1:]

    if len(encoded) > _MAX_DOC_ID_BYTES:  # encoded is pure ASCII, so len() is the byte length
        encoded = _HASHED_PREFIX + hashlib.sha256(key.encode("utf-8")).hexdigest()
    return encoded


class _IdBlock:
    """A per-process range of reserved IDs for one counter: next_id..last_id inclusive."""

    def __init__(self):
        self.lock = threading.Lock()
        self.next_id = 1
        self.last_id = 0


_id_blocks = {}
_id_blocks_lock = threading.Lock()


def _id_block(key) -> _IdBlock:
    with _id_blocks_lock:
        block = _id_blocks.get(key)
        if block is None:
            block = _id_blocks[key] = _IdBlock()
        return block


def reserve_id_block(name: str, size: int = ID_BLOCK_SIZE):
    """
    Reserve `size` IDs from counters/{name} and return the inclusive range (first, last).

    The counter's `value` is the highest ID reserved so far (a migration can preset it to the
    highest imported ID). The reservation is a single atomic increment, so concurrent processes
    never get overlapping ranges, and no transaction (or read lock) is needed: the commit
    response carries the incremented value.
    """
    if size < 1:
        raise ValueError("size must be positive")
    client = get_client()
    ref = client.collection(COUNTERS).document(name)

    for attempt in range(_RESERVE_ATTEMPTS):
        try:
            result = ref.set({"value": firestore.Increment(size)}, merge=True)
            break
        except _RESERVE_RETRYABLE:
            if attempt == _RESERVE_ATTEMPTS - 1:
                raise
            time.sleep(random.uniform(0, _RESERVE_BACKOFF_SECONDS * 2**attempt))

    last = int(firestore_helpers.decode_value(result.transform_results[0], client))
    first = last - size + 1
    if first > MAX_SAFE_ID:
        raise OverflowError(f"Counter {name!r} has exhausted the JavaScript-safe integer range")
    return first, min(last, MAX_SAFE_ID)


def allocate_id(name) -> int:
    """
    Return a new unique integer ID for entity type `name`.

    Firestore document IDs are strings, but the API (and the Flutter app) expose integer IDs.
    Rather than writing a shared counter document on every create (Firestore sustains roughly one
    write per second per document), each process reserves a block of IDs and hands them out from
    memory. IDs are unique but may have gaps and are only increasing within a process.

    This doesn't use the caller's transaction, so it can be called anywhere, including after a
    transaction's writes. An ID taken by a transaction attempt that is retried or fails is simply
    skipped.
    """

    block = _id_block((settings.GOOGLE_CLOUD_PROJECT, settings.FIRESTORE_DATABASE, name))
    with block.lock:
        if block.next_id > block.last_id:
            block.next_id, block.last_id = reserve_id_block(name)
        value = block.next_id
        block.next_id += 1
        return value


def reset_id_allocator(project=None, database=None):
    """Forget reserved ID blocks (for the given project/database, or all of them)."""
    with _id_blocks_lock:
        for key in list(_id_blocks):
            if (project is None or key[0] == project) and (database is None or key[1] == database):
                del _id_blocks[key]


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
    # The counters are gone, so blocks reserved from them would hand out stale IDs.
    reset_id_allocator(settings.GOOGLE_CLOUD_PROJECT, settings.FIRESTORE_DATABASE)

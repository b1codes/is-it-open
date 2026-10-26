"""
`firestore_usage`: counts the Firestore reads, writes and round trips a block of code makes.

It wraps the client library's RPC layer (the GAPIC `FirestoreClient`), so every call is counted,
whichever repository function or helper makes it, including those from worker threads.
"""

import threading
from contextlib import contextmanager
from dataclasses import dataclass

import pytest
from google.cloud.firestore_v1.services.firestore.client import FirestoreClient


@dataclass(frozen=True)
class Cost:
    """
    What Firestore bills for, approximately: a read for each document a query returns (at least one
    per query, even an empty one) and each document looked up by reference, found or not; a write
    for each document a commit changes. `round_trips` counts RPCs, i.e. sequential latency.
    """

    reads: int = 0
    writes: int = 0
    round_trips: int = 0


def _request(args, kwargs):
    request = kwargs.get("request", args[0] if args else None)
    return request or {}


def _field(request, name):
    return request.get(name) if isinstance(request, dict) else getattr(request, name)


class FirestoreUsage:
    def __init__(self):
        self._lock = threading.Lock()
        self._counting = False
        self._reads = self._writes = self._round_trips = 0

    def _add(self, reads=0, writes=0, round_trips=0):
        with self._lock:
            if self._counting:
                self._reads += reads
                self._writes += writes
                self._round_trips += round_trips

    @contextmanager
    def measure(self):
        """Counts what the block does; read the total from `.cost` afterwards."""
        with self._lock:
            self._reads = self._writes = self._round_trips = 0
            self._counting = True
        try:
            yield self
        finally:
            with self._lock:
                self._counting = False

    @property
    def cost(self) -> Cost:
        with self._lock:
            return Cost(self._reads, self._writes, self._round_trips)

    # Wrappers for FirestoreClient's methods

    def _documents(self, responses, has_document):
        """Passes a streamed response through, counting the documents in it (at least one read)."""
        documents = 0
        try:
            for response in responses:
                if has_document(response):
                    documents += 1
                yield response
        finally:
            self._add(reads=max(documents, 1))

    def wrap_lookup(self, original):
        # batch_get_documents: one response per requested document, `found` or `missing`; both bill a read.
        def batch_get_documents(client, *args, **kwargs):
            self._add(round_trips=1)
            return self._documents(original(client, *args, **kwargs), lambda r: r._pb.WhichOneof("result"))

        return batch_get_documents

    def wrap_query(self, original):
        # run_query: responses without a document carry only progress (e.g. the read time).
        def run_query(client, *args, **kwargs):
            self._add(round_trips=1)
            return self._documents(original(client, *args, **kwargs), lambda r: r._pb.HasField("document"))

        return run_query

    def wrap_commit(self, original):
        def commit(client, *args, **kwargs):
            self._add(writes=len(_field(_request(args, kwargs), "writes") or []), round_trips=1)
            return original(client, *args, **kwargs)

        return commit

    def wrap_round_trip(self, original):
        # Transaction bookkeeping and anything else that reads or writes no document.
        def call(client, *args, **kwargs):
            self._add(round_trips=1)
            return original(client, *args, **kwargs)

        return call


# Every FirestoreClient RPC the app could make. Anything not listed fails the test, so a new kind
# of call (e.g. an aggregation query) gets a decision on how it's billed rather than being missed.
_COUNTED = {
    "batch_get_documents": FirestoreUsage.wrap_lookup,
    "run_query": FirestoreUsage.wrap_query,
    "commit": FirestoreUsage.wrap_commit,
    "begin_transaction": FirestoreUsage.wrap_round_trip,
    "rollback": FirestoreUsage.wrap_round_trip,
}
_UNCOUNTED = (
    "batch_write",
    "create_document",
    "delete_document",
    "execute_pipeline",
    "get_document",
    "list_collection_ids",
    "list_documents",
    "listen",
    "partition_query",
    "run_aggregation_query",
    "update_document",
    "write",
)


@pytest.fixture
def firestore_usage(monkeypatch, firestore_db):
    """
    Measure what a block costs:

        with firestore_usage.measure():
            client.get("/places/bookmarks")
        assert firestore_usage.cost == Cost(reads=3, round_trips=3)
    """
    usage = FirestoreUsage()
    for name, wrap in _COUNTED.items():
        monkeypatch.setattr(FirestoreClient, name, wrap(usage, getattr(FirestoreClient, name)))
    for name in _UNCOUNTED:

        def uncounted(*args, _name=name, **kwargs):
            raise AssertionError(f"tests/performance/conftest.py doesn't count FirestoreClient.{_name} yet")

        monkeypatch.setattr(FirestoreClient, name, uncounted)
    return usage

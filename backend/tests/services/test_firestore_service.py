"""services/firestore.py: the client cache, ID reservation and contention retries, and emulator reset.

tests/test_firestore_core.py covers ID allocation under concurrency and doc_id() encoding.
"""

from unittest.mock import patch

import pytest
from google.api_core import exceptions as api_exceptions
from google.cloud.firestore_v1.document import DocumentReference
from google.cloud.firestore_v1.transaction import Transaction

from services import firestore as fs


class TestGetClient:
    @pytest.fixture(autouse=True)
    def _fake_clients(self):
        # Constructing a real client outside the emulator would look for cloud credentials.
        with patch.dict(fs._clients, clear=True), patch.object(fs.firestore, "Client") as client_class:
            client_class.side_effect = lambda project, database: (project, database)
            yield client_class

    def test_one_client_per_project_and_database(self, settings, _fake_clients):
        settings.GOOGLE_CLOUD_PROJECT = "proj-a"
        first = fs.get_client()
        assert fs.get_client() is first

        settings.FIRESTORE_DATABASE = "other-db"
        second = fs.get_client()

        assert (first, second) == (("proj-a", "(default)"), ("proj-a", "other-db"))
        assert _fake_clients.call_count == 2

    def test_points_the_client_library_at_the_emulator(self, settings, monkeypatch):
        monkeypatch.delenv("FIRESTORE_EMULATOR_HOST", raising=False)
        settings.FIRESTORE_EMULATOR_HOST = "emulator.test:1234"

        fs.get_client()

        assert fs.os.environ["FIRESTORE_EMULATOR_HOST"] == "emulator.test:1234"

    def test_production_leaves_the_environment_alone(self, settings, monkeypatch):
        monkeypatch.delenv("FIRESTORE_EMULATOR_HOST", raising=False)
        settings.FIRESTORE_EMULATOR_HOST = ""

        fs.get_client()

        assert "FIRESTORE_EMULATOR_HOST" not in fs.os.environ


class TestReserveIdBlock:
    @pytest.fixture
    def sleeps(self):
        with patch.object(fs.time, "sleep") as sleep:
            yield sleep

    @pytest.mark.parametrize("size", [0, -5])
    def test_size_must_be_positive(self, firestore_db, size):
        with pytest.raises(ValueError, match="size"):
            fs.reserve_id_block("things", size=size)

    def test_reserves_consecutive_ranges(self, firestore_db):
        assert fs.reserve_id_block("things", size=3) == (1, 3)
        assert fs.reserve_id_block("things", size=2) == (4, 5)

    @pytest.mark.parametrize("error", fs._RESERVE_RETRYABLE)
    def test_retries_transient_errors(self, firestore_db, sleeps, error):
        real_set = DocumentReference.set
        calls = []

        def flaky_set(ref, *args, **kwargs):
            calls.append(ref.path)
            if len(calls) < 3:
                raise error("transient")
            return real_set(ref, *args, **kwargs)

        with patch.object(DocumentReference, "set", flaky_set):
            assert fs.reserve_id_block("things", size=5) == (1, 5)

        assert len(calls) == 3
        assert sleeps.call_count == 2
        # Exponential backoff with jitter: attempt n waits at most base * 2**n.
        for attempt, call in enumerate(sleeps.call_args_list):
            assert 0 <= call.args[0] <= fs._RESERVE_BACKOFF_SECONDS * 2**attempt

    def test_gives_up_after_the_last_attempt(self, firestore_db, sleeps):
        with (
            patch.object(DocumentReference, "set", side_effect=api_exceptions.Aborted("contention")) as set_,
            pytest.raises(api_exceptions.Aborted),
        ):
            fs.reserve_id_block("things")

        assert set_.call_count == fs._RESERVE_ATTEMPTS
        assert sleeps.call_count == fs._RESERVE_ATTEMPTS - 1

    def test_does_not_retry_other_errors(self, firestore_db, sleeps):
        with (
            patch.object(DocumentReference, "set", side_effect=api_exceptions.PermissionDenied("no")) as set_,
            pytest.raises(api_exceptions.PermissionDenied),
        ):
            fs.reserve_id_block("things")

        assert set_.call_count == 1
        assert sleeps.call_count == 0


class TestRetryOnContention:
    @pytest.fixture
    def sleeps(self):
        with patch.object(fs.time, "sleep") as sleep:
            yield sleep

    @staticmethod
    def _failing(*errors, result="done"):
        calls = []

        def operation():
            calls.append(None)
            if len(calls) <= len(errors):
                raise errors[len(calls) - 1]
            return result

        return operation, calls

    def test_returns_the_first_success(self, sleeps):
        operation, calls = self._failing()

        assert fs.retry_on_contention(operation) == "done"
        assert len(calls) == 1
        sleeps.assert_not_called()

    def test_retries_aborted_writes_and_exhausted_transactions(self, sleeps):
        exhausted = ValueError("Failed to commit transaction in 5 attempts.")
        exhausted.__cause__ = api_exceptions.Aborted("lock timeout")
        operation, calls = self._failing(api_exceptions.Aborted("lock timeout"), exhausted)

        assert fs.retry_on_contention(operation) == "done"
        assert len(calls) == 3
        assert sleeps.call_count == 2
        assert all(0 <= call.args[0] <= fs._CONTENTION_MAX_BACKOFF_SECONDS for call in sleeps.call_args_list)

    def test_gives_up_after_the_last_attempt(self, sleeps):
        operation, calls = self._failing(*[api_exceptions.Aborted("x")] * fs._CONTENTION_ATTEMPTS)

        with pytest.raises(api_exceptions.Aborted):
            fs.retry_on_contention(operation)
        assert len(calls) == fs._CONTENTION_ATTEMPTS

    @pytest.mark.parametrize(
        "error",
        [ValueError("not contention"), api_exceptions.PermissionDenied("no"), KeyError("k")],
        ids=["plain ValueError", "PermissionDenied", "KeyError"],
    )
    def test_does_not_retry_other_errors(self, sleeps, error):
        operation, calls = self._failing(error)

        with pytest.raises(type(error)):
            fs.retry_on_contention(operation)
        assert len(calls) == 1
        sleeps.assert_not_called()


class TestRunTransaction:
    def test_commits_the_body(self, firestore_db):
        ref = fs.get_client().collection("things").document("a")

        def body(transaction):
            transaction.set(ref, {"n": 1})
            return "ok"

        assert fs.run_transaction(body) == "ok"
        assert ref.get().to_dict() == {"n": 1}

    def test_backs_off_between_aborted_commits(self, firestore_db):
        ref = fs.get_client().collection("things").document("a")
        runs = []
        real_commit = Transaction._commit
        commits = []

        def contended_commit(transaction):
            commits.append(None)
            if len(commits) <= 2:
                raise api_exceptions.Aborted("lock timeout")
            return real_commit(transaction)

        def body(transaction):
            runs.append(None)
            transaction.set(ref, {"n": len(runs)})
            return len(runs)

        with (
            patch.object(Transaction, "_commit", contended_commit),
            patch.object(Transaction, "_rollback"),
            patch.object(fs.time, "sleep") as sleep,
        ):
            assert fs.run_transaction(body) == 3
        assert sleep.call_count == 2  # each abort waits before the next attempt
        assert ref.get().to_dict() == {"n": 3}


class TestResetIdAllocator:
    @pytest.fixture(autouse=True)
    def _blocks(self):
        with patch.dict(fs._id_blocks, clear=True):
            for key in [("p1", "db1", "users"), ("p1", "db2", "users"), ("p2", "db1", "users")]:
                fs._id_block(key)
            yield

    @pytest.mark.parametrize(
        "kwargs, remaining",
        [
            ({}, set()),
            ({"project": "p1"}, {("p2", "db1", "users")}),
            ({"database": "db1"}, {("p1", "db2", "users")}),
            ({"project": "p1", "database": "db1"}, {("p1", "db2", "users"), ("p2", "db1", "users")}),
        ],
    )
    def test_forgets_matching_blocks(self, kwargs, remaining):
        fs.reset_id_allocator(**kwargs)

        assert set(fs._id_blocks) == remaining


class TestClearEmulator:
    def test_refuses_without_the_emulator(self, settings, http_mock):
        settings.FIRESTORE_EMULATOR_HOST = ""

        with pytest.raises(RuntimeError, match="FIRESTORE_EMULATOR_HOST"):
            fs.clear_emulator()
        assert len(http_mock.calls) == 0

    def test_deletes_only_the_configured_project(self, settings, http_mock):
        settings.FIRESTORE_EMULATOR_HOST = "emulator.test:8080"
        settings.GOOGLE_CLOUD_PROJECT = "demo-test"
        expected = "http://emulator.test:8080/emulator/v1/projects/demo-test/databases/(default)/documents"
        http_mock.delete(expected)

        fs.clear_emulator()

        assert [c.request.url for c in http_mock.calls] == [expected]

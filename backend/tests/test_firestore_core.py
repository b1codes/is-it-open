import threading
from unittest.mock import patch
from urllib.parse import unquote

import jwt
from google.cloud.firestore_v1.document import DocumentReference

from apps.users import repository
from apps.users.auth import GlobalAuth
from services import firestore as fs
from services.firestore import (
    ID_BLOCK_SIZE,
    MAX_SAFE_ID,
    InvalidDocumentKey,
    allocate_id,
    clear_emulator,
    doc_id,
    get_client,
    reserve_id_block,
)
from tests.base import FirestoreTestCase


def _set_counter(name, value):
    get_client().collection(fs.COUNTERS).document(name).set({"value": value})


def _counter(name):
    return get_client().collection(fs.COUNTERS).document(name).get().get("value")


def _run_threads(target, count):
    errors = []

    def run():
        try:
            target()
        except Exception as e:  # pragma: no cover - surfaced by the assertion below
            errors.append(e)

    threads = [threading.Thread(target=run) for _ in range(count)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    return errors


class IdAllocatorTest(FirestoreTestCase):
    def test_ids_are_unique_under_concurrent_threads(self):
        ids, lock = [], threading.Lock()

        def allocate_many():
            for _ in range(40):
                value = allocate_id("things")
                with lock:
                    ids.append(value)

        errors = _run_threads(allocate_many, 8)

        self.assertEqual(errors, [])
        self.assertEqual(len(ids), 320)
        self.assertEqual(len(set(ids)), 320)
        self.assertGreaterEqual(min(ids), 1)
        # The counter records the highest ID reserved, so nothing handed out is above it.
        self.assertGreaterEqual(_counter("things"), max(ids))

    def test_concurrent_block_reservations_are_disjoint(self):
        # Simulates several server processes reserving blocks from the same counter at once.
        ranges, lock = [], threading.Lock()

        def reserve():
            for _ in range(5):
                block = reserve_id_block("things", size=10)
                with lock:
                    ranges.append(block)

        errors = _run_threads(reserve, 10)

        self.assertEqual(errors, [])
        ids = [i for first, last in ranges for i in range(first, last + 1)]
        self.assertEqual(len(ids), 500)
        self.assertEqual(set(ids), set(range(1, 501)))
        self.assertEqual(_counter("things"), 500)

    def test_counter_is_written_once_per_block_not_per_create(self):
        with patch("services.firestore.reserve_id_block", wraps=reserve_id_block) as reserve:
            ids = [allocate_id("things") for _ in range(ID_BLOCK_SIZE + 1)]

        self.assertEqual(ids, list(range(1, ID_BLOCK_SIZE + 2)))
        self.assertEqual(reserve.call_count, 2)
        self.assertEqual(_counter("things"), 2 * ID_BLOCK_SIZE)

    def test_continues_from_preset_counter_value(self):
        # e.g. the Postgres import sets the counter to the highest migrated ID.
        _set_counter("saved_places", 1000)

        self.assertEqual(allocate_id("saved_places"), 1001)
        self.assertEqual(allocate_id("saved_places"), 1002)
        self.assertEqual(_counter("saved_places"), 1000 + ID_BLOCK_SIZE)

    def test_counter_stored_as_float_by_an_import_still_works(self):
        _set_counter("things", 41.0)
        self.assertEqual(reserve_id_block("things", size=1), (42, 42))

    def test_counters_are_independent(self):
        self.assertEqual(allocate_id("a"), 1)
        self.assertEqual(allocate_id("b"), 1)
        self.assertEqual(allocate_id("a"), 2)

    def test_clear_emulator_resets_in_memory_blocks(self):
        for _ in range(5):
            allocate_id("things")

        clear_emulator()

        self.assertEqual(allocate_id("things"), 1)

    def test_ids_stay_within_js_safe_integer_range(self):
        _set_counter("things", MAX_SAFE_ID - 2)

        self.assertEqual(allocate_id("things"), MAX_SAFE_ID - 1)
        self.assertEqual(allocate_id("things"), MAX_SAFE_ID)
        with self.assertRaises(OverflowError):
            allocate_id("things")


class DocIdTest(FirestoreTestCase):
    def test_ordinary_keys_keep_their_encoding(self):
        # Data written before the edge-case handling must stay reachable.
        cases = {
            "abc": "abc",
            "testuser": "testuser",
            "auth0|mock_user_123": "auth0|mock_user_123",
            "google-oauth2|1234": "google-oauth2|1234",
            "user@example.com": "user@example.com",
            "US/POI/p0/123": "US%2FPOI%2Fp0%2F123",
            "a.b": "a.b",
            "...": "...",
            "a b": "a%20b",
            "_x_": "_x_",
            "__": "__",
            "___": "___",
            "__x": "__x",
            "x__": "x__",
            "café": "caf%C3%A9",
            "0123456789abcdef0123456789abcdef01234567": "0123456789abcdef0123456789abcdef01234567",
        }
        for key, expected in cases.items():
            with self.subTest(key=key):
                self.assertEqual(doc_id(key), expected)

    def test_dot_ids_are_escaped(self):
        self.assertEqual(doc_id("."), "%2E")
        self.assertEqual(doc_id(".."), "%2E%2E")

    def test_slashes_are_escaped(self):
        self.assertEqual(doc_id("/"), "%2F")
        self.assertNotIn("/", doc_id("a/b/c"))

    def test_reserved_dunder_ids_are_escaped(self):
        self.assertEqual(doc_id("__x__"), "%5F_x__")
        self.assertEqual(doc_id("__admin__"), "%5F_admin__")
        self.assertEqual(doc_id("____"), "%5F___")
        self.assertEqual(doc_id("__a/b__"), "%5F_a%2Fb__")

    def test_overlong_keys_are_hashed(self):
        exact = "a" * 1500
        self.assertEqual(doc_id(exact), exact)

        for key in ("a" * 1501, "/" * 600, "é" * 300, "__" + "x" * 2000 + "__"):
            with self.subTest(length=len(key)):
                encoded = doc_id(key)
                self.assertTrue(encoded.startswith("%sha256:"))
                self.assertLessEqual(len(encoded.encode()), 1500)
                self.assertEqual(doc_id(key), encoded)

        self.assertNotEqual(doc_id("a" * 1501), doc_id("a" * 1502))

    def test_encoding_is_reversible_so_ids_never_collide(self):
        keys = [".", "..", "%2E", "%2E%2E", "__x__", "%5F_x__", "/", "%2F", "a b", "a%20b", "%sha256:x"]
        encoded = [doc_id(k) for k in keys]
        self.assertEqual(len(set(encoded)), len(keys))
        for key, value in zip(keys, encoded):
            with self.subTest(key=key):
                self.assertEqual(unquote(value), key)

    def test_unstorable_keys_raise(self):
        for key in ("", None, 123, "\ud800"):
            with self.subTest(key=key):
                with self.assertRaises(InvalidDocumentKey):
                    doc_id(key)

    def test_edge_case_ids_are_accepted_by_firestore(self):
        keys = [".", "..", "/", "__x__", "____", "a" * 1501, "/" * 600, "__" + "x" * 2000 + "__"]
        collection = get_client().collection("doc_id_test")
        batch = get_client().batch()
        for key in keys:
            batch.set(collection.document(doc_id(key)), {"key": key})
        batch.commit()

        for key in keys:
            with self.subTest(key=key[:20]):
                self.assertEqual(collection.document(doc_id(key)).get().get("key"), key)


class InvalidKeyApiTest(FirestoreTestCase):
    def _post(self, path, payload):
        return self.client.post(path, payload, content_type="application/json")

    def test_register_and_login_with_reserved_username(self):
        response = self._post("/api/auth/register", {"username": "__admin__", "password": "pw"})
        self.assertEqual(response.status_code, 200, response.content)
        token = response.json()["token"]

        response = self._post("/api/auth/login", {"username": "__admin__", "password": "pw"})
        self.assertEqual(response.status_code, 200, response.content)

        response = self.client.get("/api/auth/me", HTTP_AUTHORIZATION=f"Bearer {token}")
        self.assertEqual(response.status_code, 200, response.content)
        self.assertEqual(response.json()["username"], "__admin__")

    def test_register_with_unstorable_username_is_400(self):
        response = self._post("/api/auth/register", {"username": "", "password": "pw"})
        self.assertEqual(response.status_code, 400, response.content)

    def test_register_with_overlong_username(self):
        username = "u" * 2000
        response = self._post("/api/auth/register", {"username": username, "password": "pw"})
        self.assertEqual(response.status_code, 200, response.content)
        self.assertEqual(repository.get_user(username).username, username)

    def test_login_with_odd_usernames_is_401(self):
        for username in ("", "__x__", ".", "..", "/", "x" * 2000):
            with self.subTest(username=username[:20]):
                response = self._post("/api/auth/login", {"username": username, "password": "pw"})
                self.assertEqual(response.status_code, 401, response.content)

    def test_odd_bearer_tokens_are_401(self):
        for token in ("__x__", ".", "..", "a/b", "x" * 2000):
            with self.subTest(token=token[:20]):
                response = self.client.get("/api/auth/me", HTTP_AUTHORIZATION=f"Bearer {token}")
                self.assertEqual(response.status_code, 401, response.content)

    def test_lookups_return_none_for_unstorable_keys(self):
        self.assertIsNone(repository.get_user(""))
        self.assertIsNone(repository.get_user("\ud800"))
        self.assertIsNone(repository.get_user_by_token(""))
        self.assertIsNone(repository.get_user_by_token("\ud800"))
        self.assertIsNone(repository.authenticate("", "pw"))
        self.assertIsNone(GlobalAuth().authenticate(None, "__x__"))

    def test_auth0_token_with_unstorable_sub_is_rejected(self):
        token = jwt.encode({"sub": 123}, "secret", algorithm="HS256")
        with self.settings(AUTH0_MOCK=True):
            self.assertIsNone(GlobalAuth().authenticate(None, token))

    def test_token_lookup_is_one_query_on_the_user_document(self):
        user = repository.create_user("tokenuser", "pw")
        token = repository.get_or_create_token(user)

        snapshot = get_client().collection(repository.USERS).document(user.doc_id).get()
        self.assertEqual(snapshot.get("token"), token)
        with patch.object(DocumentReference, "get", autospec=True, side_effect=DocumentReference.get) as get:
            self.assertEqual(repository.get_user_by_token(token), user)
        get.assert_not_called()
        self.assertIsNone(repository.get_user_by_token(token[:-1]))
        self.assertIsNone(repository.get_user_by_token("x" * 1501))

    def test_register_rejects_auth0_style_usernames(self):
        response = self._post("/api/auth/register", {"username": "google-oauth2|123", "password": "pw"})
        self.assertEqual(response.status_code, 400, response.content)
        self.assertIsNone(repository.get_user("google-oauth2|123"))


class Auth0ReadPathTest(FirestoreTestCase):
    def setUp(self):
        super().setUp()
        self.auth = GlobalAuth()
        self.client_class = type(get_client())

    def _token(self, sub):
        return jwt.encode({"sub": sub, "email": "a@example.com"}, "secret", algorithm="HS256")

    def _patch_transactions(self):
        return patch.object(
            self.client_class, "transaction", autospec=True, side_effect=self.client_class.transaction
        )

    def test_existing_user_does_not_open_a_transaction(self):
        existing = repository.create_user("auth0|existing", email="old@example.com")

        with self.settings(AUTH0_MOCK=True), self._patch_transactions() as transaction:
            user = self.auth.authenticate(None, self._token("auth0|existing"))

        self.assertEqual(user, existing)
        transaction.assert_not_called()

    def test_new_user_is_created_in_a_transaction(self):
        with self.settings(AUTH0_MOCK=True), self._patch_transactions() as transaction:
            user = self.auth.authenticate(None, self._token("auth0|new"))

        self.assertEqual(user.username, "auth0|new")
        self.assertEqual(user.email, "a@example.com")
        self.assertTrue(transaction.called)
        self.assertEqual(repository.get_user("auth0|new"), user)

    def test_reserved_auth0_sub(self):
        with self.settings(AUTH0_MOCK=True):
            first = self.auth.authenticate(None, self._token("__x__"))
            second = self.auth.authenticate(None, self._token("__x__"))

        self.assertEqual(first, second)
        self.assertEqual(first.username, "__x__")

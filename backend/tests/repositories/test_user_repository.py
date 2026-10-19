"""apps/users/repository.py against the emulator: accounts, profiles, and API tokens."""

import threading

import pytest
from google.api_core.exceptions import Aborted
from google.cloud.firestore_v1.document import DocumentReference

from apps.users import repository as users
from services.firestore import doc_id, get_client


def _raw(username) -> dict | None:
    return get_client().collection(users.USERS).document(doc_id(username)).get().to_dict()


def _run_concurrently(target, count=5):
    """Run `target` on `count` threads released at the same moment; returns results and errors."""
    barrier = threading.Barrier(count)
    results, errors, lock = [], [], threading.Lock()

    def run():
        barrier.wait()
        try:
            value = target()
        except Exception as e:  # pragma: no cover - surfaced by the callers' assertions
            with lock:
                errors.append(e)
        else:
            with lock:
                results.append(value)

    threads = [threading.Thread(target=run) for _ in range(count)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    return results, errors


class TestCreateUser:
    def test_ids_are_sequential_integers(self, firestore_db):
        ids = [users.create_user(f"user{i}", "pw").id for i in range(3)]

        assert ids == [ids[0], ids[0] + 1, ids[0] + 2]

    def test_stores_hashed_password_and_profile(self, firestore_db):
        user = users.create_user("bob", "hunter2", email="bob@example.com", home_city="Springfield", home_lat=1.5)

        assert users.get_user("bob") == user
        raw = _raw("bob")
        assert raw["password"].startswith(("pbkdf2_", "argon2", "bcrypt", "scrypt"))
        assert (raw["email"], raw["home_city"], raw["home_lat"]) == ("bob@example.com", "Springfield", 1.5)
        assert raw["token"] is None
        assert raw["created_at"] is not None

    def test_duplicate_username_returns_none_and_keeps_the_original(self, make_user):
        original = make_user("bob", "first")

        assert users.create_user("bob", "second", email="other@example.com") is None
        assert users.get_user("bob") == original
        assert users.authenticate("bob", "first") == original

    def test_without_a_password_the_account_cannot_log_in(self, firestore_db):
        user = users.create_user("auth0|bob")

        assert not user.has_usable_password()
        assert users.authenticate("auth0|bob", "") is None

    def test_usernames_are_case_sensitive(self, make_user):
        make_user("Bob")

        assert users.create_user("bob", "pw") is not None

    def test_concurrent_creates_of_one_username_create_one_user(self, firestore_db):
        results, errors = _run_concurrently(lambda: users.create_user("bob", "pw"))

        assert errors == []
        assert len([u for u in results if u is not None]) == 1

    def test_retries_a_create_aborted_by_lock_contention(self, firestore_db, monkeypatch):
        real_create = DocumentReference.create
        calls = []

        def flaky_create(ref, document):
            calls.append(ref.id)
            if len(calls) == 1:
                raise Aborted("Transaction lock timeout.")
            return real_create(ref, document)

        monkeypatch.setattr(DocumentReference, "create", flaky_create)
        monkeypatch.setattr(users.time, "sleep", lambda _: None)

        user = users.create_user("bob", "pw")

        assert len(calls) == 2
        assert users.get_user("bob") == user

    def test_gives_up_when_every_create_is_aborted(self, firestore_db, monkeypatch):
        def aborted(ref, document):
            raise Aborted("Transaction lock timeout.")

        monkeypatch.setattr(DocumentReference, "create", aborted)
        monkeypatch.setattr(users.time, "sleep", lambda _: None)

        with pytest.raises(Aborted):
            users.create_user("bob", "pw")
        assert users.get_user("bob") is None

    @pytest.mark.parametrize("username", ["", "\ud800"])
    def test_unstorable_username_raises(self, firestore_db, username):
        with pytest.raises(users.InvalidDocumentKey):
            users.create_user(username, "pw")


class TestGetOrCreateUser:
    def test_creates_then_returns_the_same_user(self, firestore_db):
        created, was_created = users.get_or_create_user("auth0|bob", email="bob@example.com")
        again, created_again = users.get_or_create_user("auth0|bob", email="changed@example.com")

        assert (was_created, created_again) == (True, False)
        assert again == created
        assert again.email == "bob@example.com"  # defaults only apply on creation

    def test_concurrent_first_sign_ins_share_one_user(self, firestore_db):
        results, errors = _run_concurrently(lambda: users.get_or_create_user("auth0|bob"))

        assert errors == []
        assert len({user.id for user, _ in results}) == 1
        assert sum(created for _, created in results) == 1


class TestGetUser:
    def test_unknown_user(self, firestore_db):
        assert users.get_user("nobody") is None

    @pytest.mark.parametrize("username", ["", "\ud800"])
    def test_unstorable_username(self, firestore_db, username):
        assert users.get_user(username) is None

    def test_ignores_fields_the_dataclass_does_not_have(self, make_user):
        make_user("bob")
        get_client().collection(users.USERS).document("bob").update({"legacy_field": 1})

        assert users.get_user("bob").username == "bob"


class TestAuthenticate:
    def test_correct_password(self, make_user):
        user = make_user("bob", "pw")

        assert users.authenticate("bob", "pw") == user

    @pytest.mark.parametrize("username, password", [("bob", "wrong"), ("bob", ""), ("nobody", "pw"), ("", "pw")])
    def test_wrong_credentials(self, make_user, username, password):
        make_user("bob", "pw")

        assert users.authenticate(username, password) is None


class TestTokens:
    def test_token_is_created_once(self, make_user):
        user = make_user("bob")

        token = users.get_or_create_token(user)

        assert len(token) == 40 and int(token, 16) >= 0
        assert users.get_or_create_token(user) == token
        assert users.get_or_create_token(users.get_user("bob")) == token
        assert _raw("bob")["token"] == token

    def test_stale_user_object_gets_the_stored_token(self, make_user):
        stale = make_user("bob")  # loaded before any token existed
        token = users.get_or_create_token(users.get_user("bob"))

        assert users.get_or_create_token(stale) == token

    def test_concurrent_token_requests_agree(self, make_user):
        make_user("bob")

        results, errors = _run_concurrently(lambda: users.get_or_create_token(users.get_user("bob")))

        assert errors == []
        assert len(set(results)) == 1
        assert _raw("bob")["token"] == results[0]

    def test_each_user_has_their_own_token(self, make_user):
        tokens = {users.get_or_create_token(make_user()) for _ in range(3)}

        assert len(tokens) == 3

    def test_lookup_by_token(self, make_user):
        alice, bob = make_user("alice"), make_user("bob")
        alice_token, bob_token = users.get_or_create_token(alice), users.get_or_create_token(bob)

        assert users.get_user_by_token(alice_token).username == "alice"
        assert users.get_user_by_token(bob_token).username == "bob"

    @pytest.mark.parametrize(
        "token",
        [None, "", 123, "0" * 40, "x" * 1501, "\ud800"],
        ids=["none", "empty", "not-a-string", "unknown", "too-long-to-query", "unencodable"],
    )
    def test_lookup_of_invalid_tokens(self, make_user, token):
        users.get_or_create_token(make_user())

        assert users.get_user_by_token(token) is None

    def test_user_without_a_token_is_not_found_by_none(self, make_user):
        make_user("bob")  # token is None in the document

        assert users.get_user_by_token(None) is None


class TestSaveUser:
    def test_saves_profile_fields(self, make_user):
        user = make_user("bob")
        user.first_name, user.home_lat, user.use_current_location = "Bob", 1.5, True

        users.save_user(user)

        stored = users.get_user("bob")
        assert (stored.first_name, stored.home_lat, stored.use_current_location) == ("Bob", 1.5, True)

    def test_only_saves_the_named_fields(self, make_user):
        user = make_user("bob")
        user.first_name, user.last_name = "Bob", "Smith"

        users.save_user(user, {"last_name"})

        stored = users.get_user("bob")
        assert (stored.first_name, stored.last_name) == ("", "Smith")

    def test_empty_field_list_writes_nothing(self, make_user):
        user = make_user("bob")
        user.first_name = "Bob"

        users.save_user(user, set())

        assert users.get_user("bob").first_name == ""

    def test_never_writes_identity_or_credentials(self, make_user):
        user = make_user("bob", "pw")
        token = users.get_or_create_token(user)
        user.id, user.password, user.token = 999, "plaintext", "forged"

        users.save_user(user)

        stored = users.get_user("bob")
        assert stored.id != 999
        assert stored.check_password("pw")
        assert stored.token == token

    @pytest.mark.parametrize("field", ["id", "username", "password", "token", "nonexistent"])
    def test_rejects_protected_or_unknown_fields(self, make_user, field):
        with pytest.raises(ValueError, match=field):
            users.save_user(make_user(), {field})

    def test_only_changes_that_users_document(self, make_user):
        alice, bob = make_user("alice"), make_user("bob")
        alice.first_name = "Changed"

        users.save_user(alice)

        assert users.get_user("bob") == bob

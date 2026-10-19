"""/api/auth: login, register, and the signed-in user's profile (GET/PUT /me)."""

import re
from urllib.parse import unquote

import pytest
from responses import matchers

from apps.users import repository as users
from tests.conftest import TOMTOM_BASE, TOMTOM_KEY, ApiClient

GEOCODE_URL = re.compile(rf"{re.escape(TOMTOM_BASE)}/geocode/.+\.json")

PROFILE_FIELDS = {
    "email",
    "first_name",
    "last_name",
    "home_address",
    "home_street",
    "home_city",
    "home_state",
    "home_zip",
    "home_lat",
    "home_lng",
    "work_address",
    "work_street",
    "work_city",
    "work_state",
    "work_zip",
    "work_lat",
    "work_lng",
    "use_current_location",
    "calendar_subscription_url",
}


def _field_errors(response):
    """The fields a 422 response complains about."""
    assert response.status_code == 422, response.content
    return {err["loc"][-1] for err in response.json()["detail"]}


# --- POST /auth/register ---


class TestRegister:
    def test_creates_user_and_returns_token_and_profile(self, api_client):
        response = api_client.post("/auth/register", {"username": "bob", "password": "pw", "email": "bob@example.com"})

        assert response.status_code == 200
        data = response.json()
        assert set(data) == {"token", "username", "id"} | PROFILE_FIELDS
        assert data["username"] == "bob"
        assert data["email"] == "bob@example.com"
        assert isinstance(data["id"], int)
        assert users.get_user_by_token(data["token"]).username == "bob"

    def test_email_is_optional(self, api_client):
        response = api_client.post("/auth/register", {"username": "bob", "password": "pw", "email": None})

        assert response.status_code == 200
        assert response.json()["email"] == ""

    def test_password_is_stored_hashed(self, api_client):
        api_client.post("/auth/register", {"username": "bob", "password": "hunter2"})

        stored = users.get_user("bob")
        assert stored.password != "hunter2"
        assert stored.check_password("hunter2")

    def test_users_get_distinct_ids_and_tokens(self, api_client):
        first = api_client.post("/auth/register", {"username": "bob", "password": "pw"}).json()
        second = api_client.post("/auth/register", {"username": "carol", "password": "pw"}).json()

        assert first["id"] != second["id"]
        assert first["token"] != second["token"]

    def test_duplicate_username_is_409(self, api_client, user):
        response = api_client.post("/auth/register", {"username": user.username, "password": "other"})

        assert response.status_code == 409
        assert response.json() == {"detail": "Username already taken"}
        assert users.get_user(user.username).check_password("password")  # original account untouched

    @pytest.mark.parametrize("username", ["auth0|123", "google-oauth2|victim"])
    def test_auth0_style_username_is_422(self, api_client, username):
        response = api_client.post("/auth/register", {"username": username, "password": "pw"})

        assert _field_errors(response) == {"username"}
        assert users.get_user(username) is None

    def test_empty_username_is_422(self, api_client):
        response = api_client.post("/auth/register", {"username": "", "password": "pw"})

        assert _field_errors(response) == {"username"}

    @pytest.mark.parametrize(
        "payload, fields",
        [
            ({"password": "pw"}, {"username"}),
            ({"username": "bob"}, {"password"}),
            ({"username": ["bob"], "password": "pw"}, {"username"}),
            ({"username": 5, "password": "pw"}, {"username"}),
            ({"username": "bob", "password": "pw", "email": False}, {"email"}),
        ],
    )
    def test_invalid_body_is_422(self, api_client, payload, fields):
        assert _field_errors(api_client.post("/auth/register", payload)) == fields

    def test_malformed_json_is_400(self, api_client):
        response = api_client.post("/auth/register", "not json")

        assert response.status_code == 400
        assert response.json() == {"detail": "Cannot parse request body"}

    @pytest.mark.parametrize("body", ["[]", '["bob", "pw"]', '"bob"', "5", "null"])
    def test_body_that_is_not_an_object_is_400(self, api_client, body):
        response = api_client.post("/auth/register", body)

        assert response.status_code == 400
        assert response.json() == {"detail": "Cannot parse request body"}


# --- POST /auth/login ---


class TestLogin:
    def test_returns_existing_token_and_profile(self, api_client, user):
        token = users.get_or_create_token(user)

        response = api_client.post("/auth/login", {"username": "alice", "password": "password"})

        assert response.status_code == 200
        data = response.json()
        assert data["token"] == token
        assert data["id"] == user.id
        assert data["first_name"] == "Alice"

    def test_issues_a_token_on_first_login(self, api_client, user):
        response = api_client.post("/auth/login", {"username": "alice", "password": "password"})

        assert response.status_code == 200
        assert users.get_user_by_token(response.json()["token"]) == users.get_user("alice")

    def test_wrong_password_is_401(self, api_client, user):
        response = api_client.post("/auth/login", {"username": "alice", "password": "wrong"})

        assert response.status_code == 401

    def test_unknown_user_is_401_not_404(self, api_client):
        # Same response as a wrong password, so login doesn't reveal which usernames exist.
        response = api_client.post("/auth/login", {"username": "nobody", "password": "password"})

        assert response.status_code == 401

    def test_auth0_account_cannot_log_in_with_a_password(self, api_client, auth0_client):
        for password in ("", "password", "!"):
            response = api_client.post("/auth/login", {"username": auth0_client.user.username, "password": password})
            assert response.status_code == 401

    @pytest.mark.parametrize(
        "payload, fields",
        [({"username": "alice"}, {"password"}), ({"password": "pw"}, {"username"}), ({}, {"username", "password"})],
    )
    def test_invalid_body_is_422(self, api_client, payload, fields):
        assert _field_errors(api_client.post("/auth/login", payload)) == fields


# --- GET /auth/me ---


class TestGetMe:
    def test_returns_the_signed_in_user(self, any_auth_client):
        response = any_auth_client.get("/auth/me")

        assert response.status_code == 200
        data = response.json()
        assert data["id"] == any_auth_client.user.id
        assert data["username"] == any_auth_client.user.username
        assert data["email"] == "alice@example.com"
        # The token the client should keep using is the one it authenticated with.
        assert data["token"] == any_auth_client.token

    def test_auth0_profile_is_filled_from_the_token(self, auth0_client):
        data = auth0_client.get("/auth/me").json()

        assert data["username"] == "auth0|alice"
        assert (data["first_name"], data["last_name"]) == ("Alice", "Liddell")

    def test_returns_stored_profile(self, make_user):
        user = make_user(home_address="1 Home St", home_lat=40.0, home_lng=-74.0, use_current_location=True)
        client = ApiClient(users.get_or_create_token(user))

        data = client.get("/auth/me").json()

        assert (data["home_address"], data["home_lat"], data["home_lng"]) == ("1 Home St", 40.0, -74.0)
        assert data["use_current_location"] is True

    @pytest.mark.parametrize("token", [None, "not-a-token", "eyJhbGciOiJub25lIn0.e30.", "eyJ.bad.jwt"])
    def test_missing_or_invalid_credentials_are_401(self, firestore_db, token):
        assert ApiClient(token).get("/auth/me").status_code == 401

    def test_non_bearer_scheme_is_401(self, auth_client):
        response = auth_client._client.get("/api/auth/me", headers={"Authorization": f"Token {auth_client.token}"})

        assert response.status_code == 401


# --- PUT /auth/me ---


class TestUpdateMe:
    def test_updates_only_the_given_fields(self, any_auth_client):
        response = any_auth_client.put(
            "/auth/me", {"last_name": "Smith", "use_current_location": True, "calendar_subscription_url": "https://c"}
        )

        assert response.status_code == 200
        data = response.json()
        assert data["first_name"] == "Alice"  # unchanged
        assert data["last_name"] == "Smith"
        assert data["use_current_location"] is True
        assert data["calendar_subscription_url"] == "https://c"
        stored = users.get_user(any_auth_client.user.username)
        assert (stored.first_name, stored.last_name, stored.use_current_location) == ("Alice", "Smith", True)

    def test_empty_body_changes_nothing(self, auth_client):
        before = auth_client.get("/auth/me").json()

        response = auth_client.put("/auth/me", {})

        assert response.status_code == 200
        assert response.json() == before

    def test_empty_strings_clear_fields(self, auth_client):
        response = auth_client.put("/auth/me", {"first_name": ""})

        assert response.json()["first_name"] == ""
        assert users.get_user("alice").first_name == ""

    def test_does_not_change_credentials(self, auth_client):
        auth_client.put("/auth/me", {"first_name": "Al", "home_lat": 1.0, "home_lng": 2.0})

        stored = users.get_user("alice")
        assert stored.check_password("password")
        assert stored.token == auth_client.token

    def test_explicit_coordinates_are_stored_without_geocoding(self, auth_client, tomtom):
        response = auth_client.put(
            "/auth/me",
            {"home_street": "1 Main St", "home_lat": 1.5, "home_lng": 2.5, "work_city": "Paris", "work_lat": 48.8},
        )

        assert response.status_code == 200
        data = response.json()
        assert (data["home_lat"], data["home_lng"], data["work_lat"]) == (1.5, 2.5, 48.8)
        assert data["home_street"] == "1 Main St"
        assert len(tomtom.calls) == 0

    def test_home_address_change_is_geocoded(self, auth_client, tomtom):
        tomtom.get(
            GEOCODE_URL,
            json={"results": [{"position": {"lat": 39.78, "lon": -89.65}}]},
            match=[matchers.query_param_matcher({"key": TOMTOM_KEY, "limit": "1"})],
        )

        response = auth_client.put(
            "/auth/me",
            {"home_street": "1 Main St", "home_city": "Springfield", "home_state": "IL", "home_zip": "62701"},
        )

        assert response.status_code == 200
        assert (response.json()["home_lat"], response.json()["home_lng"]) == (39.78, -89.65)
        assert response.json()["work_lat"] is None
        (call,) = tomtom.calls
        assert "1 Main St, Springfield, IL, 62701" in unquote(call.request.url)
        stored = users.get_user("alice")
        assert (stored.home_lat, stored.home_lng) == (39.78, -89.65)

    def test_work_address_change_is_geocoded(self, auth_client, tomtom):
        tomtom.get(GEOCODE_URL, json={"results": [{"position": {"lat": 48.85, "lon": 2.35}}]})

        response = auth_client.put("/auth/me", {"work_city": "Paris", "work_state": "IDF"})

        assert (response.json()["work_lat"], response.json()["work_lng"]) == (48.85, 2.35)
        assert response.json()["home_lat"] is None
        assert "Paris, IDF" in unquote(tomtom.calls[0].request.url)

    def test_home_and_work_are_geocoded_separately(self, auth_client, tomtom):
        def by_address(request):
            lat = 1.0 if "Home" in unquote(request.url) else 2.0
            return 200, {}, f'{{"results": [{{"position": {{"lat": {lat}, "lon": {lat}}}}}]}}'

        tomtom.add_callback("GET", GEOCODE_URL, callback=by_address)

        data = auth_client.put("/auth/me", {"home_city": "Hometown", "work_city": "Worktown"}).json()

        assert (data["home_lat"], data["work_lat"]) == (1.0, 2.0)
        assert len(tomtom.calls) == 2

    def test_unchanged_address_is_not_geocoded_again(self, make_user, tomtom):
        user = make_user(home_city="Springfield", home_lat=1.0, home_lng=2.0)
        client = ApiClient(users.get_or_create_token(user))

        response = client.put("/auth/me", {"home_city": "Springfield"})

        assert (response.json()["home_lat"], response.json()["home_lng"]) == (1.0, 2.0)
        assert len(tomtom.calls) == 0

    def test_free_text_address_alone_is_not_geocoded(self, auth_client, tomtom):
        # Only the structured parts (street/city/state/zip) are geocoded.
        response = auth_client.put("/auth/me", {"home_address": "Somewhere nice"})

        assert response.json()["home_address"] == "Somewhere nice"
        assert response.json()["home_lat"] is None
        assert len(tomtom.calls) == 0

    @pytest.mark.parametrize(
        "geocode",
        [{"json": {"results": []}}, {"status": 500}, {"body": "not json"}],
        ids=["no-match", "server-error", "malformed"],
    )
    def test_failed_geocode_keeps_the_address_and_old_coordinates(self, make_user, tomtom, geocode):
        user = make_user(home_lat=1.0, home_lng=2.0)
        client = ApiClient(users.get_or_create_token(user))
        tomtom.get(GEOCODE_URL, **geocode)

        response = client.put("/auth/me", {"home_city": "Nowhere"})

        assert response.status_code == 200
        assert response.json()["home_city"] == "Nowhere"
        assert (response.json()["home_lat"], response.json()["home_lng"]) == (1.0, 2.0)

    def test_geocoding_is_skipped_without_a_tomtom_key(self, auth_client, http_mock):
        response = auth_client.put("/auth/me", {"home_city": "Springfield"})

        assert response.status_code == 200
        assert response.json()["home_lat"] is None
        assert len(http_mock.calls) == 0

    @pytest.mark.parametrize(
        "payload, fields",
        [
            ({"home_lat": "north"}, {"home_lat"}),
            ({"use_current_location": "sometimes"}, {"use_current_location"}),
            ({"first_name": ["A"], "work_lng": {}}, {"first_name", "work_lng"}),
            # Values of the wrong JSON type used to be coerced (0 -> false, "1.5" -> 1.5).
            ({"use_current_location": 0}, {"use_current_location"}),
            ({"home_lat": "1.5"}, {"home_lat"}),
        ],
    )
    def test_invalid_body_is_422(self, auth_client, payload, fields):
        assert _field_errors(auth_client.put("/auth/me", payload)) == fields
        assert users.get_user("alice").first_name == "Alice"

    # These used to succeed as a no-op: Ninja read any body that wasn't an object as {}.
    @pytest.mark.parametrize("body", ["[null, null]", "[1, 2]", '"Alice"', "5", "null"])
    def test_body_that_is_not_an_object_is_400(self, auth_client, body):
        response = auth_client.put("/auth/me", body)

        assert response.status_code == 400
        assert response.json() == {"detail": "Cannot parse request body"}

    @pytest.mark.parametrize("token", [None, "not-a-token"])
    def test_missing_or_invalid_credentials_are_401(self, firestore_db, token):
        assert ApiClient(token).put("/auth/me", {"first_name": "Mallory"}).status_code == 401

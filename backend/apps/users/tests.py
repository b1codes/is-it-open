import json

from apps.users import repository
from tests.base import FirestoreTestCase


class AuthApiTests(FirestoreTestCase):
    def _post(self, path, payload):
        return self.client.post(path, data=json.dumps(payload), content_type="application/json")

    def test_register_creates_user_with_default_profile(self):
        response = self._post(
            "/api/auth/register", {"username": "testuser", "password": "password", "email": "t@example.com"}
        )
        self.assertEqual(response.status_code, 200)
        data = response.json()

        self.assertIsInstance(data["id"], int)
        self.assertTrue(data["token"])
        self.assertEqual(data["email"], "t@example.com")
        self.assertEqual(data["home_address"], "")
        self.assertIsNone(data["home_lat"])
        self.assertFalse(data["use_current_location"])

        user = repository.get_user("testuser")
        self.assertNotEqual(user.password, "password")  # stored hashed
        self.assertTrue(user.check_password("password"))

    def test_register_rejects_duplicate_username(self):
        self._post("/api/auth/register", {"username": "testuser", "password": "password"})
        response = self._post("/api/auth/register", {"username": "testuser", "password": "other"})
        self.assertEqual(response.status_code, 409)

    def test_login_returns_same_token(self):
        registered = self._post("/api/auth/register", {"username": "testuser", "password": "password"}).json()

        response = self._post("/api/auth/login", {"username": "testuser", "password": "password"})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["token"], registered["token"])
        self.assertEqual(response.json()["id"], registered["id"])

    def test_login_rejects_bad_password(self):
        self._post("/api/auth/register", {"username": "testuser", "password": "password"})
        response = self._post("/api/auth/login", {"username": "testuser", "password": "wrong"})
        self.assertEqual(response.status_code, 401)

    def test_me_with_token(self):
        token = self._post("/api/auth/register", {"username": "testuser2", "password": "password"}).json()["token"]

        response = self.client.get("/api/auth/me", HTTP_AUTHORIZATION=f"Bearer {token}")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["username"], "testuser2")
        self.assertEqual(response.json()["token"], token)

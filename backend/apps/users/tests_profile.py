from django.test import TestCase, Client
from django.contrib.auth.models import User
from apps.users.models import AuthToken, UserProfile
import json
from unittest.mock import patch

class ProfileApiTest(TestCase):
    def setUp(self):
        self.client = Client()
        self.user = User.objects.create_user(username="testuser", password="password", email="test@example.com")
        self.token = AuthToken.objects.create(user=self.user)
        # Ensure profile exists with some data
        self.profile = UserProfile.objects.create(
            user=self.user,
            home_address="123 Home St",
            home_lat=40.7128,
            home_lng=-74.0060,
            calendar_subscription_url="https://example.com/cal.ics"
        )
        self.auth_headers = {"HTTP_AUTHORIZATION": f"Bearer {self.token.key}"}

    def test_get_me_returns_all_fields(self):
        """Verify GET /auth/me returns coordinates and calendar URL."""
        response = self.client.get("/api/auth/me", **self.auth_headers)
        self.assertEqual(response.status_code, 200)
        data = response.json()
        
        self.assertEqual(data["home_lat"], 40.7128)
        self.assertEqual(data["home_lng"], -74.0060)
        self.assertEqual(data["calendar_subscription_url"], "https://example.com/cal.ics")

    @patch("apps.users.api.TomTomClient.geocode_address")
    def test_update_me_geocodes_and_returns_coords(self, mock_geocode):
        """Verify PUT /auth/me triggers geocoding and returns new coordinates."""
        mock_geocode.return_value = {"lat": 34.0522, "lon": -118.2437}
        
        payload = {
            "home_street": "New St",
            "home_city": "Los Angeles",
            "home_state": "CA"
        }
        
        response = self.client.put(
            "/api/auth/me",
            data=json.dumps(payload),
            content_type="application/json",
            **self.auth_headers
        )
        
        self.assertEqual(response.status_code, 200)
        data = response.json()
        
        self.assertEqual(data["home_lat"], 34.0522)
        self.assertEqual(data["home_lng"], -118.2437)
        
        # Verify DB update
        self.profile.refresh_from_db()
        self.assertEqual(self.profile.home_lat, 34.0522)

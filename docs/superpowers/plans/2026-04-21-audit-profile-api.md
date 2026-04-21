# Audit Profile API for Coordinate Delivery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ensure the `/auth/me` endpoints (GET and PUT) consistently deliver geocoded coordinates and all profile fields.

**Architecture:** Update the Django Ninja API handlers in `backend/apps/users/api.py` to include missing fields in the response dictionaries and verify correctness with automated tests using mocks for external geocoding services.

**Tech Stack:** Python, Django, Django Ninja, Pytest/Django TestCase, Mock.

---

### Task 1: Create Failing Profile Tests

**Files:**
- Create: `backend/apps/users/tests_profile.py`

- [ ] **Step 1: Write the failing tests**

```python
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `python backend/manage.py test apps.users.tests_profile`
Expected: FAIL (KeyError: 'calendar_subscription_url' or assertion mismatch for coordinates)

---

### Task 2: Fix GET Profile Endpoint

**Files:**
- Modify: `backend/apps/users/api.py`

- [ ] **Step 1: Add missing fields to GET /me**

Update the `me` function return dictionary:
```python
@router.get("/me", response=AuthOutput, auth=GlobalAuth())
def me(request):
    # ... existing logic to get token and ensure profile ...
    return {
        "token": token,
        "username": request.user.username,
        "id": request.user.id,
        "email": request.user.email,
        "first_name": request.user.first_name,
        "last_name": request.user.last_name,
        "home_address": request.user.profile.home_address,
        "home_street": request.user.profile.home_street,
        "home_city": request.user.profile.home_city,
        "home_state": request.user.profile.home_state,
        "home_zip": request.user.profile.home_zip,
        "home_lat": request.user.profile.home_lat,
        "home_lng": request.user.profile.home_lng,
        "work_address": request.user.profile.work_address,
        "work_street": request.user.profile.work_street,
        "work_city": request.user.profile.work_city,
        "work_state": request.user.profile.work_state,
        "work_zip": request.user.profile.work_zip,
        "work_lat": request.user.profile.work_lat,
        "work_lng": request.user.profile.work_lng,
        "use_current_location": request.user.profile.use_current_location,
        "calendar_subscription_url": request.user.profile.calendar_subscription_url # ADD THIS
    }
```

- [ ] **Step 2: Run tests**

Run: `python backend/manage.py test apps.users.tests_profile.ProfileApiTest.test_get_me_returns_all_fields`
Expected: PASS

---

### Task 3: Verify and Commit

- [ ] **Step 1: Run all profile tests**

Run: `python backend/manage.py test apps.users.tests_profile`
Expected: All tests pass.

- [ ] **Step 2: Run all backend tests for regression**

Run: `python backend/manage.py test`
Expected: All tests pass.

- [ ] **Step 3: Commit changes**

```bash
git add backend/apps/users/api.py backend/apps/users/tests_profile.py
git commit -m "feat(backend): ensure profile api delivers coordinates and calendar url"
```

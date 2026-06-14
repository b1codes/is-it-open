from django.test import TestCase
from django.contrib.auth.models import User
from django.conf import settings
from apps.users.auth import GlobalAuth
from apps.users.models import AuthToken
import jwt

class Auth0BackendTest(TestCase):
    def setUp(self):
        self.auth = GlobalAuth()
        self.user = User.objects.create_user(username="localuser", password="password")
        self.local_token = AuthToken.objects.create(user=self.user)

    def test_local_token_validation(self):
        # Verify that normal local tokens still authenticate successfully
        user = self.auth.authenticate(None, self.local_token.key)
        self.assertEqual(user, self.user)
        self.assertEqual(user.username, "localuser")

    def test_local_token_validation_invalid(self):
        # Verify that an invalid local token returns None
        user = self.auth.authenticate(None, "invalid_local_token")
        self.assertIsNone(user)

    def test_mock_auth0_token_new_user(self):
        # Generate a mock JWT token
        payload = {
            "sub": "auth0|mock_user_123",
            "email": "mockuser@example.com",
            "given_name": "Mock",
            "family_name": "User"
        }
        token = jwt.encode(payload, "secret", algorithm="HS256")
        
        # Verify mock auth0 authentication
        with self.settings(AUTH0_MOCK=True):
            user = self.auth.authenticate(None, token)
            
            # Check user is created and properties mapped
            self.assertIsNotNone(user)
            self.assertEqual(user.username, "auth0|mock_user_123")
            self.assertEqual(user.email, "mockuser@example.com")
            self.assertEqual(user.first_name, "Mock")
            self.assertEqual(user.last_name, "User")
            self.assertFalse(user.has_usable_password())
            
            # Check UserProfile is automatically created
            self.assertTrue(hasattr(user, 'profile'))

    def test_mock_auth0_token_existing_user(self):
        # Create an existing user with Auth0 sub username
        sub = "auth0|existing_user_456"
        existing_user = User.objects.create_user(username=sub, email="old@example.com")
        
        payload = {
            "sub": sub,
            "email": "new@example.com",
            "given_name": "UpdatedName"
        }
        token = jwt.encode(payload, "secret", algorithm="HS256")
        
        with self.settings(AUTH0_MOCK=True):
            user = self.auth.authenticate(None, token)
            
            # Check we retrieved the existing user (doesn't create a duplicate)
            self.assertEqual(user, existing_user)
            self.assertEqual(user.username, sub)

    def test_invalid_jwt_token(self):
        # An invalid JWT (starts with eyJ but malformed or invalid structure)
        token = "eyJinvalid.token.here"
        
        with self.settings(AUTH0_MOCK=True):
            user = self.auth.authenticate(None, token)
            self.assertIsNone(user)

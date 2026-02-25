from django.db import models
from django.conf import settings
import secrets

class AuthToken(models.Model):
    user = models.OneToOneField(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='auth_token')
    key = models.CharField(max_length=40, unique=True)
    created_at = models.DateTimeField(auto_now_add=True)

    def save(self, *args, **kwargs):
        if not self.key:
            self.key = self.generate_key()
        return super().save(*args, **kwargs)

    @classmethod
    def generate_key(cls):
        return secrets.token_hex(20)

    def __str__(self):
        return self.key


class UserProfile(models.Model):
    """Profile for authenticated users with address info."""
    user = models.OneToOneField(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='profile')
    city = models.CharField(max_length=100, blank=True, default='')
    state = models.CharField(max_length=100, blank=True, default='')
    country = models.CharField(max_length=100, blank=True, default='')
    street = models.CharField(max_length=255, blank=True, default='')

    # New Location Fields
    home_address = models.CharField(max_length=255, blank=True, default='')
    home_lat = models.FloatField(null=True, blank=True)
    home_lng = models.FloatField(null=True, blank=True)
    
    work_address = models.CharField(max_length=255, blank=True, default='')
    work_lat = models.FloatField(null=True, blank=True)
    work_lng = models.FloatField(null=True, blank=True)
    
    use_current_location = models.BooleanField(default=False)

    def __str__(self):
        return f"Profile for {self.user.username}"

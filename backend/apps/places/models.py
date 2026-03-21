from django.db import models
from django.conf import settings

class Place(models.Model):
    tomtom_id = models.CharField(max_length=255, unique=True)
    name = models.CharField(max_length=255)
    address = models.CharField(max_length=512)
    latitude = models.FloatField()
    longitude = models.FloatField()
    phone = models.CharField(max_length=50, null=True, blank=True)
    website = models.URLField(max_length=500, null=True, blank=True)
    categories = models.JSONField(default=list, blank=True)

    def __str__(self):
        return self.name

class SavedPlace(models.Model):
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='saved_places')
    place = models.ForeignKey(Place, on_delete=models.CASCADE, related_name='saved_by')
    custom_name = models.CharField(max_length=255, blank=True, null=True)
    icon = models.CharField(max_length=50, blank=True, null=True)
    color = models.CharField(max_length=20, blank=True, null=True)
    is_pinned = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        unique_together = ('user', 'place')

    def __str__(self):
        return f"{self.user} - {self.custom_name or self.place.name}"

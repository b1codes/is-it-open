"""
One-shot rewrite of business hours stored before the API checked them. See backend/README_DEPLOY.md,
"Upgrading from a version that didn't check hours".

    python manage.py backfill_hours

Converts each place's hours to the API's 24-hour HH:MM ("9:00" and "9am" become "09:00") and drops
entries that can't be read. The API converts them the same way as it reads them, so this only stores
the result. Re-running it changes nothing.
"""

from django.core.management.base import BaseCommand

from apps.places import repository as places_repo


class Command(BaseCommand):
    help = "Convert business hours stored before the API checked them to HH:MM, dropping unreadable ones."

    def handle(self, *args, **options):
        updated = places_repo.backfill_hours()
        self.stdout.write(f"Updated the hours of {updated} place(s).")

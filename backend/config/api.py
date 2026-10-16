from ninja import NinjaAPI

from apps.calendar.api import router as calendar_router
from apps.places.api import router as places_router
from apps.users.api import router as users_router
from apps.users.auth import GlobalAuth

api = NinjaAPI()

# Auth Router (Login/Register) - Public
api.add_router("/auth", users_router)

# Places Router - Protected
api.add_router("/places", places_router, auth=GlobalAuth())

# Calendar Router - Protected
api.add_router("/calendar", calendar_router, auth=GlobalAuth())

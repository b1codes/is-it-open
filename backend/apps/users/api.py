import re
import time
from typing import Annotated

from ninja import Field, Router, Schema
from ninja.errors import HttpError

from config.schemas import ErrorSchema, StrictSchema
from services.firestore import InvalidDocumentKey
from services.tomtom import GeocodeUnavailable, TomTomClient

from . import repository
from .auth import GlobalAuth

router = Router()


class LoginInput(StrictSchema):
    username: str
    password: str


class AuthOutput(Schema):
    token: str
    username: str
    id: int
    email: str | None = None
    first_name: str | None = None
    last_name: str | None = None
    home_address: str | None = ""
    home_street: str | None = ""
    home_city: str | None = ""
    home_state: str | None = ""
    home_zip: str | None = ""
    home_lat: float | None = None
    home_lng: float | None = None
    work_address: str | None = ""
    work_street: str | None = ""
    work_city: str | None = ""
    work_state: str | None = ""
    work_zip: str | None = ""
    work_lat: float | None = None
    work_lng: float | None = None
    use_current_location: bool = False
    calendar_subscription_url: str | None = ""


def _auth_output(user, token):
    return {
        "token": token,
        "username": user.username,
        "id": user.id,
        "email": user.email,
        "first_name": user.first_name,
        "last_name": user.last_name,
        "home_address": user.home_address,
        "home_street": user.home_street,
        "home_city": user.home_city,
        "home_state": user.home_state,
        "home_zip": user.home_zip,
        "home_lat": user.home_lat,
        "home_lng": user.home_lng,
        "work_address": user.work_address,
        "work_street": user.work_street,
        "work_city": user.work_city,
        "work_state": user.work_state,
        "work_zip": user.work_zip,
        "work_lat": user.work_lat,
        "work_lng": user.work_lng,
        "use_current_location": user.use_current_location,
        "calendar_subscription_url": user.calendar_subscription_url,
    }


def _request_token(request, user):
    return getattr(request, "auth_token", None) or repository.get_or_create_token(user)


@router.post("/login", response={200: AuthOutput, 401: ErrorSchema})
def login(request, data: LoginInput):
    user = repository.authenticate(data.username, data.password)
    if not user:
        raise HttpError(401, "Invalid credentials")

    return _auth_output(user, repository.get_or_create_token(user))


# Auth0 subs ("provider|id") share the users/ namespace with local usernames, and Auth0 sign-in
# looks users up by sub, so a local account must never be able to claim one.
AUTH0_SUB_SEPARATOR = "|"


class RegisterInput(StrictSchema):
    username: str = Field(min_length=1, pattern=rf"^[^{re.escape(AUTH0_SUB_SEPARATOR)}]+$")
    password: str
    email: str | None = None


@router.post("/register", response={200: AuthOutput, 400: ErrorSchema, 409: ErrorSchema})
def register(request, data: RegisterInput):
    try:
        user = repository.create_user(data.username, data.password, email=data.email or "")
    except InvalidDocumentKey:
        raise HttpError(400, "Invalid username") from None
    if not user:
        raise HttpError(409, "Username already taken")

    return _auth_output(user, repository.get_or_create_token(user))


@router.get("/me", response=AuthOutput, auth=GlobalAuth())
def me(request):
    return _auth_output(request.auth, _request_token(request, request.auth))


# The bounds LocationSchema (apps.places.api) has. Unbounded, a home_lat of 1000 was stored, and the
# app's map asserted on it.
Latitude = Annotated[float, Field(ge=-90, le=90)]
Longitude = Annotated[float, Field(ge=-180, le=180)]


class ProfileUpdateInput(StrictSchema):
    first_name: str | None = None
    last_name: str | None = None
    home_address: str | None = None
    home_street: str | None = None
    home_city: str | None = None
    home_state: str | None = None
    home_zip: str | None = None
    home_lat: Latitude | None = None
    home_lng: Longitude | None = None
    work_address: str | None = None
    work_street: str | None = None
    work_city: str | None = None
    work_state: str | None = None
    work_zip: str | None = None
    work_lat: Latitude | None = None
    work_lng: Longitude | None = None
    use_current_location: bool | None = None
    calendar_subscription_url: str | None = None


# How long a pending geocode waits after a failed attempt before an update that doesn't change the
# address tries it again.
GEOCODE_RETRY_SECONDS = 10 * 60


@router.put("/me", response=AuthOutput, auth=GlobalAuth())
def update_me(request, data: ProfileUpdateInput):
    user = request.auth
    # Only the fields this request changes are written, so a concurrent update to other fields
    # (e.g. during the geocode call below) isn't overwritten with the values loaded at auth time.
    changed = set()

    def set_field(field, value):
        if value != getattr(user, field):
            setattr(user, field, value)
            changed.add(field)

    if data.first_name is not None:
        set_field("first_name", data.first_name)
    if data.last_name is not None:
        set_field("last_name", data.last_name)

    # We will track if address fields changed to determine if we need to geocode. One whose geocode
    # is pending (it changed while TomTom couldn't be asked; see below) is geocoded again, but only
    # once its last failed attempt is GEOCODE_RETRY_SECONDS old: retried on every update, each profile
    # save (a name, the calendar URL) waited on TomTom's timeouts for as long as it was down. Editing
    # the address geocodes it straight away, as always.
    now = time.time()

    def retry_due(prefix):
        failed_at = getattr(user, f"{prefix}_geocode_failed_at")
        return getattr(user, f"{prefix}_geocode_pending") and (
            failed_at is None or now - failed_at >= GEOCODE_RETRY_SECONDS
        )

    home_address_changed = retry_due("home")
    work_address_changed = retry_due("work")

    # Define fields that trigger geocoding
    home_geo_fields = ["home_street", "home_city", "home_state", "home_zip"]
    work_geo_fields = ["work_street", "work_city", "work_state", "work_zip"]

    # Handle home address fields. The free-text address isn't geocoded, so it doesn't move the coordinates.
    for field in ["home_address"] + home_geo_fields:
        val = getattr(data, field)
        if val is not None and val != getattr(user, field):
            set_field(field, val)
            home_address_changed = home_address_changed or field in home_geo_fields

    # Handle work address fields
    for field in ["work_address"] + work_geo_fields:
        val = getattr(data, field)
        if val is not None and val != getattr(user, field):
            set_field(field, val)
            work_address_changed = work_address_changed or field in work_geo_fields

    # Allow explicit lat/lng overrides from frontend: new coordinates are used instead of geocoding.
    # The stored ones sent back unchanged (as app builds from before the profile screens sent only
    # the fields they change resend their cached profile) don't choose them, so an address edited in
    # the same request, or whose geocode is pending, is still geocoded. Only while one was pending did
    # that hold, so an edited street sent with the cached profile kept the old address's coordinates.
    # Home coordinates sent with use_current_location=true are the device's position, though, which
    # "Use Current Location" sends on purpose, and they can be the stored ones (turned on again where
    # it was before). As an echo, a pending geocode then moved Home from the device to the address.
    def override_coordinates(prefix):
        given = {f: v for f in (f"{prefix}_lat", f"{prefix}_lng") if (v := getattr(data, f)) is not None}
        device_position = prefix == "home" and data.use_current_location is True
        echoed = not device_position and all(getattr(user, f) == v for f, v in given.items())
        if not given or echoed:
            return False
        for field, val in given.items():
            set_field(field, val)
        set_field(f"{prefix}_geocode_pending", False)
        set_field(f"{prefix}_geocode_failed_at", None)
        return True

    if override_coordinates("home"):
        home_address_changed = False
    if override_coordinates("work"):
        work_address_changed = False

    if data.use_current_location is not None:
        set_field("use_current_location", data.use_current_location)
    if data.calendar_subscription_url is not None:
        set_field("calendar_subscription_url", data.calendar_subscription_url)

    # Perform geocoding if needed. The old coordinates belong to the old address, so an address
    # that's cleared or that TomTom has no match for has none. If TomTom can't be asked (an outage,
    # no API key), the old ones are kept, rather than lost, and the geocode is pending: a later update
    # tries again (see retry_due), whatever it changes, until it gets an answer or coordinates are given.
    if home_address_changed or work_address_changed:
        client = TomTomClient()

        for prefix, changed_address, geo_fields in (
            ("home", home_address_changed, home_geo_fields),
            ("work", work_address_changed, work_geo_fields),
        ):
            if not changed_address:
                continue
            full_address = ", ".join(p for p in (getattr(user, f) for f in geo_fields) if p)
            try:
                coords = client.geocode_address(full_address) if full_address else None
            except GeocodeUnavailable:
                set_field(f"{prefix}_geocode_pending", True)
                set_field(f"{prefix}_geocode_failed_at", now)
                continue
            set_field(f"{prefix}_lat", coords["lat"] if coords else None)
            set_field(f"{prefix}_lng", coords["lon"] if coords else None)
            set_field(f"{prefix}_geocode_pending", False)
            set_field(f"{prefix}_geocode_failed_at", None)

    if changed:
        repository.save_user(user, changed)

    return _auth_output(user, _request_token(request, user))

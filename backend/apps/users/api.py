from ninja import Router, Schema
from ninja.errors import HttpError

from services.firestore import InvalidDocumentKey
from services.tomtom import TomTomClient

from . import repository
from .auth import GlobalAuth

router = Router()


class LoginInput(Schema):
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


class RegisterInput(Schema):
    username: str
    password: str
    email: str | None = None


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


@router.post("/login", response=AuthOutput)
def login(request, data: LoginInput):
    user = repository.authenticate(data.username, data.password)
    if not user:
        raise HttpError(401, "Invalid credentials")

    return _auth_output(user, repository.get_or_create_token(user))


# Auth0 subs ("provider|id") share the users/ namespace with local usernames, and Auth0 sign-in
# looks users up by sub, so a local account must never be able to claim one.
AUTH0_SUB_SEPARATOR = "|"


@router.post("/register", response=AuthOutput)
def register(request, data: RegisterInput):
    if AUTH0_SUB_SEPARATOR in data.username:
        raise HttpError(400, "Invalid username") from None
    try:
        user = repository.create_user(data.username, data.password, email=data.email or "")
    except InvalidDocumentKey:
        raise HttpError(400, "Invalid username") from None
    if not user:
        raise HttpError(400, "Username already taken")

    return _auth_output(user, repository.get_or_create_token(user))


@router.get("/me", response=AuthOutput, auth=GlobalAuth())
def me(request):
    return _auth_output(request.auth, _request_token(request, request.auth))


class ProfileUpdateInput(Schema):
    first_name: str | None = None
    last_name: str | None = None
    home_address: str | None = None
    home_street: str | None = None
    home_city: str | None = None
    home_state: str | None = None
    home_zip: str | None = None
    home_lat: float | None = None
    home_lng: float | None = None
    work_address: str | None = None
    work_street: str | None = None
    work_city: str | None = None
    work_state: str | None = None
    work_zip: str | None = None
    work_lat: float | None = None
    work_lng: float | None = None
    use_current_location: bool | None = None
    calendar_subscription_url: str | None = None


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

    # We will track if address fields changed to determine if we need to geocode
    home_address_changed = False
    work_address_changed = False

    # Define fields that trigger geocoding
    home_geo_fields = ["home_street", "home_city", "home_state", "home_zip"]
    work_geo_fields = ["work_street", "work_city", "work_state", "work_zip"]

    # Handle home address fields
    for field in ["home_address"] + home_geo_fields:
        val = getattr(data, field)
        if val is not None and val != getattr(user, field):
            set_field(field, val)
            home_address_changed = True

    # Handle work address fields
    for field in ["work_address"] + work_geo_fields:
        val = getattr(data, field)
        if val is not None and val != getattr(user, field):
            set_field(field, val)
            work_address_changed = True

    # Allow explicit lat/lng overrides from frontend. Don't re-geocode if coordinates are
    # provided, even if they're the same values.
    for field in ("home_lat", "home_lng"):
        val = getattr(data, field)
        if val is not None:
            set_field(field, val)
            home_address_changed = False
    for field in ("work_lat", "work_lng"):
        val = getattr(data, field)
        if val is not None:
            set_field(field, val)
            work_address_changed = False

    if data.use_current_location is not None:
        set_field("use_current_location", data.use_current_location)
    if data.calendar_subscription_url is not None:
        set_field("calendar_subscription_url", data.calendar_subscription_url)

    # Perform geocoding if needed
    if home_address_changed or work_address_changed:
        client = TomTomClient()

        if home_address_changed:
            address_parts = [p for p in [user.home_street, user.home_city, user.home_state, user.home_zip] if p]
            full_address = ", ".join(address_parts)
            if full_address:
                coords = client.geocode_address(full_address)
                if coords:
                    set_field("home_lat", coords["lat"])
                    set_field("home_lng", coords["lon"])

        if work_address_changed:
            address_parts = [p for p in [user.work_street, user.work_city, user.work_state, user.work_zip] if p]
            full_address = ", ".join(address_parts)
            if full_address:
                coords = client.geocode_address(full_address)
                if coords:
                    set_field("work_lat", coords["lat"])
                    set_field("work_lng", coords["lon"])

    if changed:
        repository.save_user(user, changed)

    return _auth_output(user, _request_token(request, user))

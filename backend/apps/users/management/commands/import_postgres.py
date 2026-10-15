"""
One-shot import of the legacy Postgres/PostGIS database (the Django ORM version of the app) into
Firestore. See backend/README_DEPLOY.md, "Upgrading from the Postgres version".

    uv run --group postgres-import python manage.py import_postgres --dry-run
    uv run --group postgres-import python manage.py import_postgres

Reads the old tables

    auth_user + users_userprofile + users_authtoken   ->  users/{doc}, auth_tokens/{doc}
    places_place + hours_businesshours                ->  places/{doc} (hours embedded)
    places_savedplace                                 ->  users/{doc}/saved_places/{doc}

and writes documents in the same shapes as apps.users.repository and apps.places.repository,
keeping the original integer IDs (the Flutter app caches them), the Django password hashes and the
API token keys. The ID counters are moved up to the largest Postgres ID (skipped rows included) so new
records continue the old sequences and no ID a client has seen is handed out again.

The import is idempotent: every document is written whole with set(), so re-running it converges on
the same state. It refuses to write if Firestore already holds a record under the same key with a
different ID, or a different record with an imported ID, because overwriting either would break IDs
clients hold.

The Postgres half (read_postgres) is separate from the Firestore half (build_plan / find_conflicts /
apply_plan) so the latter can be tested against the emulator with fixture rows.
"""
import datetime
from dataclasses import asdict, dataclass, field

from decouple import config
from django.conf import settings
from django.core.management.base import BaseCommand, CommandError
from google.cloud import firestore

from apps.places import repository as places_repo
from apps.users import repository as users_repo
from services.firestore import COUNTERS, InvalidDocumentKey, doc_id, get_client

# Firestore's limit on writes in one batch.
BATCH_SIZE = 500

# Rows read from Postgres. Column names match the old models; see read_postgres() for the queries.


@dataclass
class LegacyData:
    users: list = field(default_factory=list)  # auth_user joined with users_userprofile and users_authtoken
    places: list = field(default_factory=list)  # places_place with the PostGIS location as lat / lng
    hours: list = field(default_factory=list)  # hours_businesshours
    saved_places: list = field(default_factory=list)  # places_savedplace


_PROFILE_COLUMNS = (
    "home_address", "home_street", "home_city", "home_state", "home_zip", "home_lat", "home_lng",
    "work_address", "work_street", "work_city", "work_state", "work_zip", "work_lat", "work_lng",
    "use_current_location", "calendar_subscription_url",
)

USERS_SQL = f"""
    SELECT u.id, u.username, u.password, u.email, u.first_name, u.last_name, u.is_active, u.date_joined,
           t.key AS token_key, t.created_at AS token_created_at,
           {", ".join(f"p.{c}" for c in _PROFILE_COLUMNS)}
    FROM auth_user u
    LEFT JOIN users_authtoken t ON t.user_id = u.id
    LEFT JOIN users_userprofile p ON p.user_id = u.id
    ORDER BY u.id
"""

PLACES_SQL = """
    SELECT id, tomtom_id, name, address,
           ST_Y(location::geometry) AS lat, ST_X(location::geometry) AS lng,
           phone, website, categories
    FROM places_place
    ORDER BY id
"""

HOURS_SQL = """
    SELECT place_id, day_of_week, open_time, close_time
    FROM hours_businesshours
    ORDER BY place_id, day_of_week, open_time
"""

SAVED_PLACES_SQL = """
    SELECT id, user_id, place_id, custom_name, icon, color, is_pinned, is_check_it_out,
           average_visit_length, created_at
    FROM places_savedplace
    ORDER BY id
"""


def read_postgres(database_url: str) -> LegacyData:
    """Read every legacy table in one read-only, repeatable-read transaction (a consistent snapshot)."""
    try:
        import psycopg
        from psycopg.rows import dict_row
    except ImportError as exc:
        raise CommandError(
            "psycopg is not installed. Install the optional group: "
            "`uv sync --group postgres-import` (or run with `uv run --group postgres-import ...`)."
        ) from exc

    # dj-database-url spells PostGIS URLs postgis://; libpq only knows postgres(ql)://.
    if database_url.startswith("postgis://"):
        database_url = "postgresql://" + database_url[len("postgis://"):]

    with psycopg.connect(database_url, row_factory=dict_row) as conn:
        conn.read_only = True
        conn.isolation_level = psycopg.IsolationLevel.REPEATABLE_READ
        with conn.transaction():
            return LegacyData(
                users=conn.execute(USERS_SQL).fetchall(),
                places=conn.execute(PLACES_SQL).fetchall(),
                hours=conn.execute(HOURS_SQL).fetchall(),
                saved_places=conn.execute(SAVED_PLACES_SQL).fetchall(),
            )


# Firestore half


KINDS = (users_repo.USERS, places_repo.PLACES, places_repo.SAVED_PLACES)


@dataclass
class Plan:
    writes: list = field(default_factory=list)  # (DocumentReference, data)
    # kind -> {document path: integer ID}, for the conflict check and the counters
    ids: dict = field(default_factory=lambda: {kind: {} for kind in KINDS})
    tokens: int = 0  # token documents planned
    tokens_read: int = 0
    read: dict = field(default_factory=lambda: dict.fromkeys(KINDS, 0))
    skipped: dict = field(default_factory=lambda: dict.fromkeys(KINDS, 0))
    warnings: list = field(default_factory=list)
    # kind -> largest ID in Postgres, skipped rows included, so no ID a client has seen is reused
    counters: dict = field(default_factory=dict)

    def add(self, kind, ref, data):
        if ref.path in self.ids[kind]:
            raise CommandError(f"Two legacy {kind} rows map to the same document {ref.path}")
        self.ids[kind][ref.path] = data["id"]
        self.writes.append((ref, data))


def _time(value) -> str:
    return value if isinstance(value, str) else value.isoformat(timespec="minutes")


def _or_server_timestamp(value):
    return value if isinstance(value, datetime.datetime) else firestore.SERVER_TIMESTAMP


def _place_timestamps(data: LegacyData) -> dict:
    """
    places_place has no creation time, but recent_places() orders by `created_at` (the old code
    ordered by ID). Give each place a stand-in one millisecond apart in ID order, ending at the
    newest timestamp in the legacy data, so the order is kept, every imported place sorts before
    places created afterwards, and re-runs write the same values.
    """
    stamps = [
        row.get(column)
        for rows, column in ((data.users, "date_joined"), (data.users, "token_created_at"), (data.saved_places, "created_at"))
        for row in rows
    ]
    stamps = [s for s in stamps if isinstance(s, datetime.datetime)]
    end = max(stamps) if stamps else datetime.datetime.now(datetime.timezone.utc)
    ids = sorted(row["id"] for row in data.places)
    return {place_id: end - datetime.timedelta(milliseconds=len(ids) - i) for i, place_id in enumerate(ids)}


def build_plan(data: LegacyData, include_inactive: bool = False) -> Plan:
    """Turn legacy rows into the documents the repositories would have written for them."""
    client = get_client()
    plan = Plan()
    rows = {users_repo.USERS: data.users, places_repo.PLACES: data.places, places_repo.SAVED_PLACES: data.saved_places}
    plan.read = {kind: len(r) for kind, r in rows.items()}
    plan.tokens_read = sum(1 for row in data.users if row.get("token_key"))
    plan.counters = {kind: max(row["id"] for row in r) for kind, r in rows.items() if r}

    users_by_id = {}
    for row in data.users:
        # The old login rejected inactive accounts; the Firestore model has no such flag.
        if not include_inactive and row.get("is_active") is False:
            plan.skipped[users_repo.USERS] += 1
            continue
        # NULL profile columns (no UserProfile row) fall back to the dataclass defaults.
        user = users_repo.User.from_dict({k: v for k, v in row.items() if v is not None})
        user.token = row.get("token_key") or None
        try:
            ref = client.collection(users_repo.USERS).document(user.doc_id)
        except InvalidDocumentKey as exc:
            plan.skipped[users_repo.USERS] += 1
            plan.warnings.append(f"Skipped user {row['id']} ({row['username']!r}): {exc}")
            continue
        users_by_id[row["id"]] = user

        plan.add(users_repo.USERS, ref, {**asdict(user), "created_at": _or_server_timestamp(row.get("date_joined"))})
        if user.token:
            token_ref = client.collection(users_repo.AUTH_TOKENS).document(doc_id(user.token))
            plan.writes.append((
                token_ref,
                {"username": user.username, "created_at": _or_server_timestamp(row.get("token_created_at"))},
            ))
            plan.tokens += 1

    hours_by_place = {}
    for row in data.hours:
        hours_by_place.setdefault(row["place_id"], []).append({
            "day_of_week": row["day_of_week"],
            "open_time": _time(row["open_time"]),
            "close_time": _time(row["close_time"]),
        })

    created_at = _place_timestamps(data)
    places_by_id = {}
    for row in data.places:
        try:
            ref = places_repo._places().document(doc_id(row["tomtom_id"]))
        except InvalidDocumentKey as exc:
            plan.skipped[places_repo.PLACES] += 1
            plan.warnings.append(f"Skipped place {row['id']} ({row['tomtom_id']!r}): {exc}")
            continue
        place = {
            "id": row["id"],
            "tomtom_id": row["tomtom_id"],
            "name": row["name"],
            "search_terms": places_repo._search_terms(row["name"]),
            "address": row["address"],
            "phone": row.get("phone"),
            "website": row.get("website"),
            "categories": row.get("categories") or [],
            "hours": places_repo._normalize_hours(hours_by_place.get(row["id"], [])),
            "created_at": created_at[row["id"]],
            **places_repo._location_fields(row["lat"], row["lng"]),
        }
        places_by_id[row["id"]] = place
        plan.add(places_repo.PLACES, ref, place)

    for row in data.saved_places:
        user, place = users_by_id.get(row["user_id"]), places_by_id.get(row["place_id"])
        if user is None or place is None:
            plan.skipped[places_repo.SAVED_PLACES] += 1
            continue
        saved = {
            "id": row["id"],
            "place_id": place["id"],
            "tomtom_id": place["tomtom_id"],
            **{f: row.get(f) for f in places_repo._SAVED_PLACE_FIELDS},
            "is_pinned": bool(row.get("is_pinned")),
            "is_check_it_out": bool(row.get("is_check_it_out")),
            "created_at": _or_server_timestamp(row.get("created_at")),
        }
        ref = places_repo._saved_places(user).document(doc_id(place["tomtom_id"]))
        plan.add(places_repo.SAVED_PLACES, ref, saved)

    return plan


def _existing(kind):
    client = get_client()
    query = client.collection_group(kind) if kind == places_repo.SAVED_PLACES else client.collection(kind)
    for snapshot in query.select(["id"]).stream():
        yield snapshot.reference.path, (snapshot.to_dict() or {}).get("id")


def find_conflicts(plan: Plan) -> list:
    """
    Records already in Firestore that the import would overwrite with a different ID, or whose ID the
    import would hand to a different record. Re-running the import over its own output finds none.
    """
    conflicts = []
    for kind in KINDS:
        planned = plan.ids[kind]
        path_by_id = {i: path for path, i in planned.items()}
        for path, existing_id in _existing(kind):
            if path in planned:
                if existing_id != planned[path]:
                    conflicts.append(f"{path} has id {existing_id} in Firestore but {planned[path]} in Postgres")
            elif existing_id in path_by_id:
                conflicts.append(f"{path} already uses {kind} id {existing_id}, which belongs to {path_by_id[existing_id]}")
    return conflicts


def apply_plan(plan: Plan):
    """Write every document in batches, then move each ID counter up to the largest legacy ID."""
    client = get_client()
    for start in range(0, len(plan.writes), BATCH_SIZE):
        batch = client.batch()
        for ref, data in plan.writes[start:start + BATCH_SIZE]:
            batch.set(ref, data)
        batch.commit()

    @firestore.transactional
    def raise_counter(transaction, ref, value):
        snapshot = ref.get(transaction=transaction)
        # Never lower a counter: that would hand out IDs that are already taken.
        if not snapshot.exists or snapshot.get("value") < value:
            transaction.set(ref, {"value": value})

    for kind, value in plan.counters.items():
        raise_counter(client.transaction(), client.collection(COUNTERS).document(kind), value)


def firestore_counts() -> dict:
    client = get_client()

    def count(query):
        return query.count().get()[0][0].value

    return {
        users_repo.USERS: count(client.collection(users_repo.USERS)),
        users_repo.AUTH_TOKENS: count(client.collection(users_repo.AUTH_TOKENS)),
        places_repo.PLACES: count(client.collection(places_repo.PLACES)),
        places_repo.SAVED_PLACES: count(client.collection_group(places_repo.SAVED_PLACES)),
    }


def counter_values() -> dict:
    refs = [get_client().collection(COUNTERS).document(kind) for kind in KINDS]
    return {s.id: s.get("value") for s in get_client().get_all(refs) if s.exists}


class Command(BaseCommand):
    help = "Import users, tokens, places and saved places from the legacy Postgres database into Firestore."

    def add_arguments(self, parser):
        parser.add_argument(
            "--database-url",
            default=config("DATABASE_URL", default=""),
            help="Legacy Postgres URL, e.g. postgres://user:pass@db:5432/isitopen_db (default: $DATABASE_URL).",
        )
        parser.add_argument("--dry-run", action="store_true", help="Read and check everything, write nothing.")
        parser.add_argument(
            "--include-inactive",
            action="store_true",
            help="Also import users with is_active=false. Firestore has no such flag, so they could log in again.",
        )

    def handle(self, *args, database_url, dry_run, include_inactive, **options):
        if not database_url:
            raise CommandError("Pass --database-url or set DATABASE_URL to the legacy Postgres database.")
        if not settings.FIRESTORE_EMULATOR_HOST and settings.GOOGLE_CLOUD_PROJECT.startswith("demo-"):
            raise CommandError(
                f"GOOGLE_CLOUD_PROJECT is {settings.GOOGLE_CLOUD_PROJECT!r}; demo- projects only exist in the "
                "emulator. Set it to your real project ID."
            )

        target = f"project {settings.GOOGLE_CLOUD_PROJECT!r}, database {settings.FIRESTORE_DATABASE!r}"
        if settings.FIRESTORE_EMULATOR_HOST:
            target += f" (emulator at {settings.FIRESTORE_EMULATOR_HOST})"
        self.stdout.write(f"Target: {target}")

        data = read_postgres(database_url)
        plan = build_plan(data, include_inactive=include_inactive)
        for warning in plan.warnings:
            self.stderr.write(self.style.WARNING(warning))

        conflicts = find_conflicts(plan)
        if conflicts:
            shown = "\n  ".join(conflicts[:20])
            more = f"\n  ... and {len(conflicts) - 20} more" if len(conflicts) > 20 else ""
            raise CommandError(
                f"Firestore already has records that conflict with the import:\n  {shown}{more}\n"
                "Run the import against an empty database, before the new backend takes traffic."
            )

        if not dry_run:
            apply_plan(plan)
        self._report(plan, None if dry_run else firestore_counts())

        if dry_run:
            self.stdout.write(self.style.WARNING("Dry run: nothing was written."))
        else:
            self.stdout.write(f"ID counters: {counter_values()}")
            self.stdout.write(self.style.SUCCESS("Import complete."))

    def _report(self, plan, counts):
        planned = {kind: len(plan.ids[kind]) for kind in KINDS}
        planned[users_repo.AUTH_TOKENS] = plan.tokens
        read = {**plan.read, users_repo.AUTH_TOKENS: plan.tokens_read}
        skipped = {**plan.skipped, users_repo.AUTH_TOKENS: plan.tokens_read - plan.tokens}
        written = "written" if counts is not None else "to write"

        rows = [("", "postgres", "skipped", written, "firestore", "counter")]
        for kind in (users_repo.USERS, users_repo.AUTH_TOKENS, places_repo.PLACES, places_repo.SAVED_PLACES):
            rows.append((
                kind,
                read[kind],
                skipped[kind],
                planned[kind],
                "-" if counts is None else counts[kind],
                plan.counters.get(kind, "-"),
            ))
        for row in rows:
            self.stdout.write("  " + f"{row[0]:<14}" + "".join(f"{v!s:>11}" for v in row[1:]))

        if counts is not None:
            short = [k for k, v in planned.items() if counts[k] < v]
            if short:
                raise CommandError(f"Firestore has fewer documents than were written for: {', '.join(short)}")

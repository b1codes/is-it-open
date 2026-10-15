# Deploying to AWS EC2

This guide explains how to deploy the backend to an AWS EC2 instance using Docker and Docker Compose.
App data lives in Google Cloud Firestore.

**Upgrading an existing deployment that still runs on Postgres?** Read
[section 7](#7-upgrading-from-the-postgres-version) first. Starting the new backend without importing
the old data loses every account, saved place and token.

## 1. Prepare your EC2 Instance
- **OS**: Ubuntu 22.04 LTS (recommended)
- **Security Group**:
  - Inbound rules:
    - HTTP (80) or HTTPS (443) (if using Nginx/ALB)
    - Custom TCP (8000) (if exposing backend directly)
    - SSH (22)
- **Install Docker with the Compose v2 plugin** (Compose 2.24 or newer, for `env_file` with `required:`):
  ```bash
  curl -fsSL https://get.docker.com | sudo sh
  sudo usermod -aG docker $USER
  # Log out and log back in for group changes to take effect
  docker compose version
  ```
  The legacy `docker-compose` v1 package can't read these compose files.

## 2. Clone the Repository
```bash
git clone <your-repo-url>
cd is-it-open
```

## 3. Set Up Firestore and Credentials
1. In the Google Cloud console, create (or pick) a project and create a Firestore database in **Native mode**.
2. Create a service account with the **Cloud Datastore User** role.
3. Give the backend credentials. It uses [Application Default Credentials](https://cloud.google.com/docs/authentication/application-default-credentials), so pick one:
   - **On Google Cloud** (Compute Engine, GKE, ...): attach the service account to the VM or workload.
     The metadata server provides credentials and no key file is needed. Use
     `docker-compose.prod.yml` on its own.
   - **Anywhere else** (e.g. EC2): download a JSON key for the service account (or a
     [workload identity federation](https://cloud.google.com/iam/docs/workload-identity-federation-with-other-clouds)
     credential config for AWS) and copy it to the instance as `backend/gcp-service-account.json`
     (`chmod 600`). It is gitignored and excluded from the Docker image. Add
     `docker-compose.prod.keyfile.yml` to every compose command, which mounts the file read-only and
     sets `GOOGLE_APPLICATION_CREDENTIALS`. To keep the file somewhere else, export
     `GCP_CREDENTIALS_FILE=/path/to/key.json` in your shell. It's a Compose (host) variable, so
     putting it in `backend/.env` has no effect. If the file is missing, `up` fails with
     `bind source path does not exist`; it never silently starts without credentials.

     With workload identity federation on EC2, the container reaches the instance metadata
     service through one extra network hop, so set the IMDSv2 hop limit to 2
     (`aws ec2 modify-instance-metadata-options --instance-id <id> --http-put-response-hop-limit 2`).

To avoid repeating the `-f` flags, set them once per shell:
```bash
export COMPOSE_FILE=docker-compose.prod.yml                                  # on Google Cloud
export COMPOSE_FILE=docker-compose.prod.yml:docker-compose.prod.keyfile.yml  # with a key file
```
The commands below spell out `-f docker-compose.prod.yml`. Add `-f docker-compose.prod.keyfile.yml`
when you use a key file, or drop both flags once `COMPOSE_FILE` is set.

## 4. Configure Environment Variables
`backend/.env` is the only place the production container reads settings from. Compose loads it with
`env_file`, and it's excluded from the image.

1. Copy the sample environment file:
   ```bash
   cp backend/sample.env backend/.env
   ```
2. Edit `backend/.env` with your production values:
   - `SECRET_KEY`: Generate a secure one (e.g., `openssl rand -base64 32`)
   - `ALLOWED_HOSTS`: Add your EC2 public IP or domain name
   - `TOMTOM_API_KEY`: Your TomTom API key
   - `GOOGLE_CLOUD_PROJECT`: Your GCP project ID
   - `FIRESTORE_DATABASE`: Only if you aren't using the `(default)` database. Otherwise leave the line out.
   - `CORS_ALLOW_ALL_ORIGINS`: `settings.py` doesn't read `CORS_ALLOWED_ORIGINS` yet, so with `0` every
     cross-origin browser request is refused. Set `1` if a web build of the app calls the API from
     another origin. The mobile apps aren't affected.
   - `AUTH0_DOMAIN`, `AUTH0_AUDIENCE` and `AUTH0_MOCK=0`: Without a domain, or with mock mode on, the
     backend accepts **unsigned** Auth0 tokens, so anyone could sign in as any Auth0 user.
   - Leave `FIRESTORE_EMULATOR_HOST` out. Compose forces it empty, and `DEBUG` to `0`, in production.

The container refuses to start, and logs `backend/.env: ...`, if `SECRET_KEY` or
`GOOGLE_CLOUD_PROJECT` is missing or empty, if `GOOGLE_CLOUD_PROJECT` is an emulator-only `demo-*`
project, if `FIRESTORE_DATABASE` is present but empty, or if `GOOGLE_APPLICATION_CREDENTIALS`
doesn't point at a file inside the container. If `docker compose ps` shows the backend restarting,
check `docker compose -f docker-compose.prod.yml logs backend`.

## 5. Run with Docker Compose
Use the production-specific compose file:
```bash
docker compose -f docker-compose.prod.yml up --build -d                                       # on Google Cloud
docker compose -f docker-compose.prod.yml -f docker-compose.prod.keyfile.yml up --build -d   # with a key file
```

Firestore is schemaless, so there are no migrations to run.

## 6. (Optional) Reverse Proxy
It is highly recommended to place an Nginx reverse proxy or an AWS ALB in front of port 8000.
For Nginx on the same EC2:
```nginx
server {
    listen 80;
    server_name yourdomain.com;

    location / {
        proxy_pass http://localhost:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

## 7. Upgrading from the Postgres version
Earlier versions stored everything in a PostGIS container (`db` in the old `docker-compose.prod.yml`).
`manage.py import_postgres` copies users (with their Django password hashes and profile), API
tokens, places with their hours, and saved places into Firestore. It keeps every integer ID, because
the Flutter app caches them, and moves the Firestore ID counters past the largest old IDs so new
records continue the old sequences.

Plan a short maintenance window. The steps assume the old stack's default database settings
(`POSTGRES_USER=postgres`, `POSTGRES_PASSWORD=postgres`, `POSTGRES_DB=isitopen_db`); substitute
yours if you overrode them. If the old stack was started with `docker-compose` v1, use that binary
for steps 1 to 3.

1. **Stop writes.** In the old checkout, stop the old backend but leave the database running:
   ```bash
   docker compose -f docker-compose.prod.yml stop backend
   ```
2. **Back up the database** and copy the dump off the instance (e.g. to S3):
   ```bash
   docker compose -f docker-compose.prod.yml exec -T db pg_dump -U postgres -Fc isitopen_db > ~/isitopen-$(date +%F).dump
   docker compose -f docker-compose.prod.yml exec -T db pg_restore --list < ~/isitopen-$(date +%F).dump | head   # readable?
   ```
3. **Record the row counts** to compare against later:
   ```bash
   docker compose -f docker-compose.prod.yml exec -T db psql -U postgres isitopen_db -c "
     SELECT (SELECT count(*) FROM auth_user) AS users,
            (SELECT count(*) FROM auth_user WHERE NOT is_active) AS inactive_users,
            (SELECT count(*) FROM users_authtoken) AS auth_tokens,
            (SELECT count(*) FROM places_place) AS places,
            (SELECT count(*) FROM places_savedplace) AS saved_places;"
   ```
4. **Update the code and configure Firestore** (sections 3 and 4), then build the new image. Don't
   start it yet.
   ```bash
   git pull
   docker compose -f docker-compose.prod.yml build backend
   ```
   The old `db` container keeps running. It's no longer in the compose file, so Compose warns about
   an orphan container until step 7.
5. **Dry run.** This reads Postgres and checks Firestore, but writes nothing. The psycopg driver is
   an optional dependency group, so it's installed into the throwaway container first:
   ```bash
   docker compose -f docker-compose.prod.yml run --rm --no-deps \
     -e DATABASE_URL=postgres://postgres:postgres@db:5432/isitopen_db \
     backend sh -c 'uv sync --frozen --no-dev --no-install-project --group postgres-import && python manage.py import_postgres --dry-run'
   ```
   `db` resolves because the container joins the same Compose project network as the old database
   (same directory, same project name). For a database elsewhere (e.g. RDS), point `DATABASE_URL`
   at it. Check that the `postgres` column matches step 3. Inactive users are `skipped`, along with
   their tokens and saved places, because the new backend has no "inactive" flag and would let them
   log in again. Pass `--include-inactive` to import them anyway.
6. **Import**, using the same command without `--dry-run`. Then verify the output:
   - `firestore` equals `written` for every row. The command fails if Firestore ends up with fewer
     documents. Tokens are stored on the user documents, so the `auth_tokens` row counts users
     that have one.
   - `written` equals `postgres` minus `skipped`.
   - `ID counters` shows the largest old IDs (or higher).

   The import is idempotent. Every document is rewritten whole, and counters are never lowered, so
   you can re-run it (e.g. after fixing something) as long as the new backend hasn't taken traffic.
   It aborts without writing if Firestore already holds a record under an old key with a different
   ID, or a different record using an old ID. That happens if the new backend ran against this
   database before the import. Point it at an empty database, or clear that one, and run it again.
7. **Switch traffic** by starting the new backend (add the key file override if you use one):
   ```bash
   docker compose -f docker-compose.prod.yml up -d
   ```
   Start it only after the import has finished. Each backend process reserves blocks of IDs from
   the counters on first use, so a process started earlier must be restarted
   (`docker compose -f docker-compose.prod.yml restart backend`). Sign in with an existing account and
   check that its saved places are there. Once you're confident, remove the old database container
   with `docker compose -f docker-compose.prod.yml up -d --remove-orphans`. That keeps the
   `is-it-open_postgres_data` volume. Delete the volume (`docker volume rm is-it-open_postgres_data`)
   only when you no longer need to roll back, and keep the dump.

Not imported: the old profile's unused `city`, `state`, `country` and `street` columns (the app uses
the `home_*` and `work_*` fields), `is_staff`/`is_superuser`/`last_login`, token creation times
(the tokens themselves are kept, on the user documents), and Django admin and session data.
Places get a stand-in `created_at` that keeps their old ID order for the "recent places" list.

**Rolling back**: check out the previous release and run its `docker compose -f docker-compose.prod.yml up -d`.
The Postgres volume is untouched by the import, but anything written to Firestore after the switch
isn't in Postgres.

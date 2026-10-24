# Smoke test

`smoke.py` checks that a deployed backend works end to end, in under a minute:

| Check | What it shows |
| --- | --- |
| health | `GET /health` answers (it waits up to `SMOKE_WAIT` seconds, 60 by default, for a backend that's still starting) |
| sign in | `POST /api/auth/login` and `GET /api/auth/me` work for the test account: Firestore reads, and the token round trip |
| search | `GET /api/places/search` returns results: the TomTom key works |
| bookmark round trip | saving a search result as a place, bookmarking it, listing it, and deleting it: Firestore writes |

It picks a search result the account hasn't bookmarked and deletes the bookmark again, so the account
ends as it started. (The saved place stays: places are shared, and the app saves them the same way.)
It uses only the standard library, so it runs anywhere with Python 3.11+.

## Running it

```sh
SMOKE_USERNAME=... SMOKE_PASSWORD=... make smoke URL=https://api.example.com
make test-smoke    # against a running E2E stack (make e2e-up), as CI does
```

`SMOKE_QUERY` changes the search (`pizza` by default). The exit code is 0 when every check passes, 1
when one fails (the output names it), and 2 for a usage error.

## In CI

- **Every PR** that touches the app, the E2E stack or `smoke/`: the E2E job runs it against the
  E2E stack, with an account it registers, so a change that would break it fails before a deploy.
- **After a deploy and every hour:** `.github/workflows/smoke.yml` runs it against production. Deploys
  are manual for now (see `backend/README_DEPLOY.md`), so run it after each one with
  `gh workflow run smoke.yml` (or `-f base_url=...` for another backend). A deploy workflow can call
  it with `uses: ./.github/workflows/smoke.yml` and `secrets: inherit`.

  A failure opens an issue labeled `smoke-failure` (or comments on the open one), which notifies the
  repository's watchers, and the next passing run closes it. Nothing rolls back automatically yet;
  roll back as `README_DEPLOY.md` describes.

### Setting it up for production

1. Create the test account once, on the production backend:

   ```sh
   curl -X POST https://api.example.com/api/auth/register -H 'Content-Type: application/json' \
     -d '{"username": "smoke-test", "password": "<a long random password>"}'
   ```

   Use it for nothing else. The smoke test never creates accounts.
2. Add the repository secrets `SMOKE_USERNAME` and `SMOKE_PASSWORD`, and the repository variable
   `SMOKE_BASE_URL` (the backend's root URL, e.g. `https://api.example.com`). Until the variable is
   set, the hourly run is skipped.

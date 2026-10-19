# Contracts

The agreements the app depends on, committed so a change to one shows up in review and is checked automatically:

| File | Between | Checked by |
| --- | --- | --- |
| `openapi.json` | Flutter app ↔ Django backend | snapshot, provider, consumer and breaking-change checks (below) |
| `tomtom/` | Django backend ↔ TomTom Search API | recorded fixtures per PR, the live API nightly |

## The API contract (`openapi.json`)

This file is the OpenAPI schema the backend serves at `/api/openapi.json`.

| Check | Where | When |
| --- | --- | --- |
| **Snapshot.** The served schema matches the committed file. | `backend/tests/contracts/test_openapi_snapshot.py` | every PR |
| **Provider.** The backend honors the schema. Schemathesis sends valid and invalid requests to every operation and checks for no 5xx, documented statuses and bodies, invalid input rejected, and valid input accepted. | `backend/tests/contracts/test_provider.py` | every PR (50 requests per operation), nightly (1,000) |
| **Consumer.** The app agrees with the schema. Every `ApiService` method runs against a fake backend generated from it. Each request must be one the schema accepts, and each documented response (every field set; only required fields; each error) must parse into the models without losing a value. | `frontend/test/contracts/` | every PR |
| **Breaking changes.** oasdiff compares the schema against the base branch's copy. | the `API breaking changes` job in `ci.yml` | PRs that change it |

### Changing the API

1. Change the backend.
2. Run `make contracts-update` (or `UPDATE_CONTRACTS=1 uv run pytest tests/contracts/test_openapi_snapshot.py` from `backend/`), and commit the new `openapi.json` in the same PR.
3. Run the frontend tests. If a model no longer fits, update it in the same PR. If the app doesn't call a new operation, list it in `_notUsedByTheApp` in `frontend/test/contracts/api_contract_test.dart`.

### What the schema documents

- Every route's success response, with the constraints the backend enforces: patterns, bounds, and minimum lengths.
- The errors the routes raise themselves (400, 404, 409), declared in their `response=`.
- 401 on every route that needs auth, 422 on every route that takes input, and 400 on every route with a body (a body that isn't a JSON object). `config.api.Api` adds these, since Django Ninja returns them but doesn't document them.

The error bodies are `ErrorSchema` (`{"detail": "..."}`) and `ValidationErrorSchema` (`{"detail": [{"type", "loc", "msg"}, ...]}`), defined in `backend/config/schemas.py`. Request bodies subclass `StrictSchema`, so a value of the wrong JSON type is a 422 rather than being coerced (`0` for `false`).

### Breaking changes

Released builds of the app keep calling the API after a backend deploy. So when a PR changes `openapi.json`, the **API breaking changes** CI job runs [oasdiff](https://github.com/oasdiff/oasdiff) against the base branch's copy. It fails on changes that can break an existing client, such as:

- removing a route, or a field from a response
- making a response field optional or nullable
- adding a required request field, or narrowing what a parameter accepts

The job summary lists every API change, breaking or not.

To check locally:

```sh
git show origin/main:contracts/openapi.json > /tmp/base.json
docker run --rm -v "$PWD:/repo" -v /tmp:/tmp -w /repo tufin/oasdiff:v1.33.0 \
  breaking /tmp/base.json contracts/openapi.json --fail-on ERR --err-ignore contracts/breaking-changes-ignore.txt
```

When a break is intended (for example, the app versions that relied on a field are no longer supported), add the reported line to `breaking-changes-ignore.txt` in the same PR, so the reviewer sees it was a deliberate choice.

### Generated Dart models (evaluated, not adopted)

Generating the Dart models and client from `openapi.json` (e.g. `swagger_parser` or `openapi-generator`) would remove hand-written drift entirely. For now the consumer tests catch drift instead, because:

- The app's models aren't plain DTOs. They carry UI types (`TimeOfDay`, `LatLng`), `Equatable`, defaults, and helpers that screens and blocs use throughout. Generated classes would need a mapping layer, or a rewrite of every caller.
- `Place` serves both `PlaceSchema` and `PlaceCreateSchema`, and `User` serves both `AuthOutput` and the profile update. Generators produce one class per schema.
- Generators add `build_runner` and generated code to keep in sync, which is a lot for 17 operations.

Revisit this if the API grows a lot, or if the consumer tests start needing frequent updates.

## The TomTom contract (`tomtom/`)

`services/tomtom.py` reads a handful of fields from TomTom's Search API v2 (POI search, nearby search, place by ID, geocode).

- `search.schema.json` and `geocode.schema.json` describe the fields the client reads. Other fields TomTom sends are allowed.
- `fixtures/` holds responses in that shape. `backend/tests/contracts/test_tomtom_contract.py` checks the fixtures, and the responses the test factories build, against the schemas. It also checks that the client turns every fixture result into a valid place.
- Nightly, the **TomTom live contract** job sends the same requests to the real API and checks the responses still match. It needs a `TOMTOM_API_KEY` repository secret, and warns instead of running without one.

The fixtures were written from TomTom's documented response format. To re-record them from the live API (for example, after the nightly job fails because TomTom changed something):

```sh
cd backend
TOMTOM_LIVE_API_KEY=... UPDATE_CONTRACTS=1 uv run pytest tests/contracts/test_tomtom_contract.py -k live
```

Then review the diff. The exact-value assertions in `test_client_reads_every_field_of_a_recorded_place` will need the new values.

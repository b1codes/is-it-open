# API contract

`openapi.json` is the contract between the Flutter app and the Django backend: the OpenAPI schema the backend serves at `/api/openapi.json`, committed so changes to it show up in review.

## Changing the API

1. Change the backend.
2. Run `make contracts-update` (or `UPDATE_CONTRACTS=1 uv run pytest tests/contracts/test_openapi_snapshot.py` from `backend/`) and commit the new `openapi.json` in the same PR.
3. Run the frontend tests. If the models in `frontend/lib/models/` no longer fit, update them in the same PR.

The backend suite fails while `openapi.json` is out of date (`backend/tests/contracts/test_openapi_snapshot.py`), so it can't silently drift from the code.

## What the schema documents

- Every route's success response.
- The errors the routes raise themselves (400, 404), declared in their `response=`.
- 401 on every route that needs auth, and 422 on every route that takes input. `config.api.Api` adds these, since Django Ninja returns them but doesn't document them.

The error bodies are `ErrorSchema` (`{"detail": "..."}`) and `ValidationErrorSchema` (`{"detail": [{"type", "loc", "msg"}, ...]}`), defined in `backend/config/schemas.py`.

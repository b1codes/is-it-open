"""
The OpenAPI schema the backend serves matches the committed contract, contracts/openapi.json.

The Flutter client's contract tests read that file, and CI diffs it against `main` for breaking
changes, so an API change must update it in the same PR. Regenerate it with
`make contracts-update` (or `UPDATE_CONTRACTS=1 uv run pytest tests/contracts/test_openapi_snapshot.py`).
"""

import difflib
import json
import os
from pathlib import Path

import pytest
from django.test import Client

# backend/tests/contracts/ -> the repo root (in the dev container, /code/tests/contracts/ -> /,
# where docker-compose.yml mounts contracts/).
SNAPSHOT = Path(__file__).resolve().parents[3] / "contracts" / "openapi.json"


def render(schema: dict) -> str:
    return json.dumps(schema, indent=2, ensure_ascii=False) + "\n"


def test_served_schema_matches_committed_contract():
    response = Client().get("/api/openapi.json")
    assert response.status_code == 200
    served = render(response.json())

    if os.environ.get("UPDATE_CONTRACTS") == "1":
        SNAPSHOT.parent.mkdir(exist_ok=True)
        SNAPSHOT.write_text(served)
        return

    if not SNAPSHOT.exists():
        pytest.fail(f"{SNAPSHOT} is missing; run `make contracts-update` to create it.")
    committed = SNAPSHOT.read_text()
    if served != committed:
        diff = "".join(
            difflib.unified_diff(
                committed.splitlines(keepends=True),
                served.splitlines(keepends=True),
                "contracts/openapi.json (committed)",
                "/api/openapi.json (served)",
            )
        )
        pytest.fail(
            "The API no longer matches contracts/openapi.json. If the change is intended, run "
            "`make contracts-update` and commit the result (check the Flutter models still fit).\n\n" + diff
        )


def test_every_operation_documents_its_errors():
    """Clients branch on these statuses, so each one an operation can return must be in the contract."""
    schema = Client().get("/api/openapi.json").json()

    for path, operations in schema["paths"].items():
        for method, operation in operations.items():
            responses = operation["responses"]
            name = f"{method.upper()} {path}"
            assert any(code.startswith("2") for code in responses), f"{name} documents no success response"
            if operation.get("security"):
                assert "401" in responses, f"{name} needs auth but doesn't document 401"
            if operation.get("parameters") or operation.get("requestBody"):
                assert "422" in responses, f"{name} takes input but doesn't document 422"

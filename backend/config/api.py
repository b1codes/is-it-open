from ninja import NinjaAPI

from apps.calendar.api import router as calendar_router
from apps.places.api import router as places_router
from apps.users.api import router as users_router
from apps.users.auth import GlobalAuth

from .schemas import ErrorSchema, ValidationErrorSchema

COMPONENT_REF = "#/components/schemas/{model}"


def _json_response(description: str, model) -> dict:
    ref = COMPONENT_REF.format(model=model.__name__)
    return {"description": description, "content": {"application/json": {"schema": {"$ref": ref}}}}


class Api(NinjaAPI):
    """
    NinjaAPI whose OpenAPI schema also documents the errors the framework itself returns: 401 on
    every operation that needs auth, and 422 on every operation that takes input. Routes declare
    the errors they raise themselves (400, 404) in their `response=`.

    The schema is the contract with the Flutter client; see contracts/README.md.
    """

    def get_openapi_schema(self, *, path_prefix=None, path_params=None):
        schema = super().get_openapi_schema(path_prefix=path_prefix, path_params=path_params)
        for model in (ErrorSchema, ValidationErrorSchema):
            definition = model.model_json_schema(ref_template=COMPONENT_REF)
            schema["components"]["schemas"].update(definition.pop("$defs", {}))
            schema["components"]["schemas"][model.__name__] = definition

        for operations in schema["paths"].values():
            for operation in operations.values():
                responses = operation["responses"]
                if operation.get("security"):
                    responses.setdefault(401, _json_response("Unauthorized", ErrorSchema))
                if operation.get("parameters") or operation.get("requestBody"):
                    responses.setdefault(422, _json_response("Validation Error", ValidationErrorSchema))
        return schema


api = Api(
    title="Is It Open? API",
    version="1.0.0",
    description="Backend for the Is It Open? app: accounts, places and bookmarks, and calendar import.",
)

# Auth Router (Login/Register) - Public
api.add_router("/auth", users_router)

# Places Router - Protected
api.add_router("/places", places_router, auth=GlobalAuth())

# Calendar Router - Protected
api.add_router("/calendar", calendar_router, auth=GlobalAuth())

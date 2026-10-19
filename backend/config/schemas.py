"""Response bodies shared by every router, so the OpenAPI contract documents errors as well as success."""

from ninja import Schema


class ErrorSchema(Schema):
    """Body of an `HttpError` (400, 404) and of a failed authentication (401)."""

    detail: str


class ValidationErrorItem(Schema):
    type: str
    loc: list[str | int]
    msg: str


class ValidationErrorSchema(Schema):
    """Body of a 422: the request didn't match the operation's parameters or body schema."""

    detail: list[ValidationErrorItem]

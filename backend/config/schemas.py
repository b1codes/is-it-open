"""Schemas shared by every router: strict request bodies, and the error bodies the OpenAPI contract documents."""

from typing import Annotated

from ninja import Schema
from pydantic import BeforeValidator, ConfigDict


def _integral_float_to_int(value):
    return int(value) if isinstance(value, float) and value.is_integer() else value


# JSON Schema counts 1.0 as an integer, but pydantic's strict mode doesn't. Use JsonInt for int
# fields of a StrictSchema. To bound an optional one, put the Field before the validator, or the
# bounds are left out of the OpenAPI schema: `Annotated[int, Field(ge=1), INTEGRAL_FLOATS] | None`.
INTEGRAL_FLOATS = BeforeValidator(_integral_float_to_int)
JsonInt = Annotated[int, INTEGRAL_FLOATS]


class StrictSchema(Schema):
    """
    A request body (or a model nested in one). Values must already have their documented JSON type:
    by default pydantic would also take `0` for `false`, `false` for `0`, or `"1.5"` for `1.5`,
    which the contract doesn't allow. Integers are still accepted for floats.
    """

    model_config = ConfigDict(strict=True)


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

"""The port. Everything the application knows about language models.

A port is a promise, not an implementation. The application depends on this
protocol; adapters satisfy it. Swapping a provider means writing a new adapter,
never touching the code that uses one.
"""

from __future__ import annotations

from typing import Protocol

from .domain import Request, Response


class LanguageModelPort(Protocol):
    """Generate a response for a request.

    Implementations must raise `TransientError` when a retry could help and
    `PermanentError` when it could not. Leaking provider-specific exceptions
    through this boundary defeats the purpose of the port.

    Deliberately not `@runtime_checkable`: that only verifies method names, not
    signatures, so it grants confidence it cannot justify. Conformance is
    checked by the type checker and by the tests, which is where it belongs.
    """

    def generate(self, request: Request) -> Response:
        """Return the model response for `request`."""
        ...

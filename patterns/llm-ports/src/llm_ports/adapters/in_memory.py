"""In-memory adapter. The reason the whole system can be tested offline.

This is not a mock created per test. It is a real implementation of the port
whose backing store happens to live in memory. Tests exercise the same code
path production uses, minus the network.
"""

from __future__ import annotations

from collections.abc import Callable, Iterable

from ..domain import Request, Response, Usage
from ..errors import LanguageModelError


class InMemoryLanguageModel:
    """Answer from a scripted queue, a rule, or a default.

    Three ways to configure it, in order of precedence:

    1. `responses`: a queue consumed one call at a time. Use it when the test
       cares about a specific sequence.
    2. `rule`: a callable that receives the request and returns text. Use it
       when the answer depends on the input.
    3. `default`: returned when nothing else applies.

    Passing a `LanguageModelError` instance in the queue raises it instead of
    returning it, which is how failure paths get tested without a network.
    """

    def __init__(
        self,
        responses: Iterable[str | LanguageModelError] | None = None,
        rule: Callable[[Request], str] | None = None,
        default: str = "",
    ) -> None:
        self._queue: list[str | LanguageModelError] = list(responses or [])
        self._rule = rule
        self._default = default
        self.calls: list[Request] = []

    def generate(self, request: Request) -> Response:
        """Satisfy `LanguageModelPort` without leaving the process."""
        self.calls.append(request)

        if self._queue:
            nxt = self._queue.pop(0)
            if isinstance(nxt, LanguageModelError):
                raise nxt
            return self._as_response(nxt, request)

        if self._rule is not None:
            return self._as_response(self._rule(request), request)

        return self._as_response(self._default, request)

    @property
    def call_count(self) -> int:
        """How many times the port was exercised."""
        return len(self.calls)

    @property
    def last_request(self) -> Request | None:
        """The most recent request, or None if never called."""
        return self.calls[-1] if self.calls else None

    @staticmethod
    def _as_response(text: str, request: Request) -> Response:
        # Word counts stand in for tokens. Good enough to assert on, and
        # honest about not being a real tokenizer.
        prompt_words = sum(len(m.content.split()) for m in request.messages)
        return Response(
            text=text,
            usage=Usage(input_tokens=prompt_words, output_tokens=len(text.split())),
            finish_reason="stop",
        )

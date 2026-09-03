"""A use case, to show what depending on a port buys you.

Note what this file does not import: no vendor SDK, no HTTP client, no model
name. It receives a `LanguageModelPort` and that is the whole contract. The
same class runs against a remote provider in production and against the
in-memory adapter in tests, unchanged.
"""

from __future__ import annotations

import time
from collections.abc import Callable
from dataclasses import dataclass

from ..domain import Message, Request, Role
from ..errors import TransientError
from ..ports import LanguageModelPort

_INSTRUCTION = (
    "Summarise the document below. Keep it under {limit} words. "
    "Use only information present in the document."
)

# The word limit is a soft instruction to the model. The token budget is a hard
# cap on what the provider will emit. Deriving the second from the first was a
# mistake that survived two rounds of tuning before a contract test settled it:
# a model that reasons before answering spends an unknown and variable share of
# the budget thinking, so no multiplier of the word count is ever right.
#
# The budget is now set deliberately, and generously, and the caller may
# override it. `Summary.truncated` reports when even that was not enough.
_DEFAULT_OUTPUT_BUDGET = 2048

# Stop reasons that mean the answer was cut off rather than finished.
_TRUNCATED = frozenset({"length", "max_tokens", "MAX_TOKENS"})


@dataclass(frozen=True)
class Summary:
    """The result, plus what it cost to produce."""

    text: str
    attempts: int
    input_tokens: int | None = None
    output_tokens: int | None = None
    #: True when the provider stopped because the budget ran out. A truncated
    #: summary is a wrong answer, and a silent one is worse than an error.
    truncated: bool = False


class SummarizeDocument:
    """Summarise a document, retrying only what is worth retrying.

    Retries apply to `TransientError` alone. A permanent failure is raised
    immediately, because repeating a malformed request just burns budget.
    """

    def __init__(
        self,
        model: LanguageModelPort,
        max_attempts: int = 3,
        backoff_seconds: float = 0.5,
        sleep: Callable[[float], None] = time.sleep,
    ) -> None:
        if max_attempts < 1:
            raise ValueError("max_attempts must be at least 1")
        self._model = model
        self._max_attempts = max_attempts
        self._backoff = backoff_seconds
        # Injected so tests do not wait in real time.
        self._sleep = sleep

    def __call__(
        self,
        document: str,
        word_limit: int = 80,
        max_output_tokens: int | None = None,
    ) -> Summary:
        """Return a summary of `document`.

        `word_limit` is asked of the model in the instruction. `max_output_tokens`
        is the hard cap the provider enforces; leave it unset unless you have a
        reason, because a cap tuned to the word count truncates any model that
        reasons before it answers.
        """
        if not document.strip():
            raise ValueError("document must not be empty")

        request = Request(
            messages=(
                Message(role=Role.SYSTEM, content=_INSTRUCTION.format(limit=word_limit)),
                Message(role=Role.USER, content=document),
            ),
            max_output_tokens=max_output_tokens or _DEFAULT_OUTPUT_BUDGET,
            temperature=0.0,
        )

        last: TransientError | None = None
        for attempt in range(1, self._max_attempts + 1):
            try:
                response = self._model.generate(request)
            except TransientError as exc:
                last = exc
                if attempt < self._max_attempts:
                    self._sleep(self._backoff * attempt)
                continue
            return Summary(
                text=response.text,
                attempts=attempt,
                input_tokens=response.usage.input_tokens,
                output_tokens=response.usage.output_tokens,
                truncated=response.finish_reason in _TRUNCATED,
            )

        # Not an assert: `python -O` strips those, and losing this branch
        # would turn a clear failure into an obscure one.
        if last is None:  # pragma: no cover - unreachable while max_attempts >= 1
            raise RuntimeError("retry loop ended without a result or an error")
        raise last

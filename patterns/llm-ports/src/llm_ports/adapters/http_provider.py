"""HTTP adapter for any provider exposing a chat-style JSON endpoint.

Everything that identifies a vendor lives in configuration: the endpoint, the
credential and the field names. Nothing here hardcodes a provider or a model,
which is what makes the swap a config change rather than a rewrite.
"""

from __future__ import annotations

import json
import urllib.error
import urllib.request
from collections.abc import Callable
from dataclasses import dataclass, field
from email.message import Message
from typing import IO, Any, Protocol

from ..domain import Request, Response, Usage
from ..errors import ContentRejected, PermanentError, TransientError

# Status codes worth retrying. Everything else is the caller's problem.
_RETRYABLE = frozenset({408, 425, 429, 500, 502, 503, 504})

# Stop reasons that mean the budget ran out rather than the answer finished.
_TRUNCATION_REASONS = frozenset({"length", "max_tokens", "MAX_TOKENS"})

# Ceiling on how much of a response body will be read into memory. A provider
# that is broken, hostile, or simply misconfigured can otherwise exhaust the
# process: `read()` with no argument reads until the peer stops sending.
# Generous enough for any plausible completion, small enough to be survivable.
_MAX_RESPONSE_BYTES = 8 * 1024 * 1024


class HttpResponseLike(Protocol):
    """The slice of a urllib response this adapter actually uses.

    Typing the seam rather than the concrete class is what lets a test pass a
    stand-in without the type checker objecting.
    """

    def read(self, amount: int = -1, /) -> bytes: ...

    def __enter__(self) -> "HttpResponseLike": ...

    def __exit__(self, *exc_info: object) -> None: ...


# An opener is anything callable like `urllib.request.urlopen`.
Opener = Callable[..., HttpResponseLike]


class _NoRedirects(urllib.request.HTTPRedirectHandler):
    """Refuse redirects instead of following them.

    urllib re-sends the Authorization header to whatever host a redirect points
    at. A misconfigured or compromised endpoint would therefore be handed the
    credential. An endpoint that moved is a config change, not something to
    follow blindly.
    """

    def redirect_request(
        self,
        req: urllib.request.Request,
        fp: IO[bytes],
        code: int,
        msg: str,
        headers: Message,
        newurl: str,
    ) -> urllib.request.Request | None:
        """Raise instead of following, so the credential stays with one host."""
        raise urllib.error.HTTPError(
            req.full_url, code, f"refusing redirect to {newurl}", headers, fp
        )


_SAFE_OPENER = urllib.request.build_opener(_NoRedirects).open


@dataclass(frozen=True)
class HttpProviderConfig:
    """Where to call and how to read the answer.

    `response_text_path` walks the JSON response, so a provider that nests the
    text differently is accommodated by configuration alone. Steps may be
    strings (object keys) or integers (array indices): most providers wrap the
    answer in a list, and a path that only understood objects would force a
    code change for the most common shape there is.
    """

    endpoint: str
    # Kept out of repr(): a config object reaches logs and tracebacks far more
    # often than anyone expects, and a credential printed once is a credential
    # to rotate.
    api_key: str = field(repr=False)
    #: Upper bound on the response body read into memory.
    max_response_bytes: int = _MAX_RESPONSE_BYTES
    model_id: str = ""
    response_text_path: tuple[str | int, ...] = ("output", "text")
    # Request field names are configurable for the same reason the response
    # path is. Making only the response adjustable was an asymmetry that a
    # live call exposed: providers disagree on the output-budget field name
    # as readily as they disagree on where the answer sits.
    max_tokens_field: str = "max_tokens"
    temperature_field: str = "temperature"
    # Usage field names vary too. A live call reported nothing because these
    # were hardcoded, which was the same asymmetry as the request body: read
    # paths configurable, everything else assumed.
    usage_container_field: str = "usage"
    usage_input_field: str = "prompt_tokens"
    usage_output_field: str = "completion_tokens"
    timeout_seconds: float = 30.0

    def __post_init__(self) -> None:
        if not self.endpoint.startswith("https://"):
            raise ValueError("endpoint must be https")
        if not self.api_key:
            raise ValueError("api_key must not be empty")
        if not self.model_id:
            raise ValueError("model_id must not be empty")
        if self.max_response_bytes <= 0:
            raise ValueError("max_response_bytes must be positive")


class HttpLanguageModel:
    """Call a remote provider over HTTPS and map its failures onto the port."""

    def __init__(self, config: HttpProviderConfig, opener: Opener | None = None) -> None:
        self._config = config
        # Injected so tests can drive the adapter without a network. The
        # default refuses redirects, so the credential never travels to a host
        # other than the one configured.
        self._opener = opener or _SAFE_OPENER

    def generate(self, request: Request) -> Response:
        """Satisfy `LanguageModelPort` against a remote endpoint."""
        payload = json.dumps(self._to_wire(request)).encode("utf-8")
        http_request = urllib.request.Request(
            self._config.endpoint,
            data=payload,
            headers={
                "Content-Type": "application/json",
                "Authorization": f"Bearer {self._config.api_key}",
            },
            method="POST",
        )

        try:
            with self._opener(http_request, timeout=self._config.timeout_seconds) as raw:
                body = json.loads(self._read_bounded(raw).decode("utf-8"))
        except urllib.error.HTTPError as exc:
            raise self._classify(exc, self._read_error_body(exc)) from exc
        except (urllib.error.URLError, TimeoutError) as exc:
            raise TransientError(f"provider unreachable: {exc}") from exc
        except json.JSONDecodeError as exc:
            raise PermanentError("provider returned a body that is not JSON") from exc

        return self._from_wire(body)

    def _to_wire(self, request: Request) -> dict[str, Any]:
        return {
            "model": self._config.model_id,
            "messages": [
                {"role": m.role.value, "content": m.content} for m in request.messages
            ],
            self._config.max_tokens_field: request.max_output_tokens,
            self._config.temperature_field: request.temperature,
        }

    def _from_wire(self, body: dict[str, Any]) -> Response:
        finish_reason = self._finish_reason(body)

        try:
            node: object = body
            for step in self._config.response_text_path:
                node = self._descend(node, step)
        except PermanentError:
            # A provider that ran out of budget before emitting anything may
            # omit the text field entirely. That is an empty answer, not a
            # malformed request, and calling it permanent would send the caller
            # looking for a bug that is not there.
            if finish_reason in _TRUNCATION_REASONS:
                node = ""
            else:
                raise

        if not isinstance(node, str):
            raise PermanentError("response text field is not a string")

        raw_usage = body.get(self._config.usage_container_field)
        usage = raw_usage if isinstance(raw_usage, dict) else {}
        return Response(
            text=node,
            usage=Usage(
                input_tokens=usage.get(self._config.usage_input_field),
                output_tokens=usage.get(self._config.usage_output_field),
            ),
            finish_reason=finish_reason,
        )

    @staticmethod
    def _finish_reason(body: dict[str, Any]) -> str | None:
        """Read the stop reason, whether it sits at the root or inside a choice."""
        if isinstance(body.get("finish_reason"), str):
            return str(body["finish_reason"])
        choices = body.get("choices")
        if isinstance(choices, list) and choices and isinstance(choices[0], dict):
            reason = choices[0].get("finish_reason")
            if isinstance(reason, str):
                return reason
        return None

    def _read_bounded(self, raw: HttpResponseLike) -> bytes:
        """Read the body, refusing anything past the configured ceiling.

        One byte past the limit is requested on purpose: it is the only way to
        tell a body that exactly fills the budget from one that was truncated
        by it, and silently accepting a cut-off body would produce a JSON error
        that points at the wrong cause.
        """
        limit = self._config.max_response_bytes
        payload = raw.read(limit + 1)
        if len(payload) > limit:
            raise PermanentError(
                f"response exceeds {limit} bytes; refusing to buffer it"
            )
        return payload

    def _describe_path(self) -> str:
        return ".".join(str(step) for step in self._config.response_text_path)

    def _descend(self, node: object, step: str | int) -> object:
        """Take one step through the response, into an object or an array."""
        if isinstance(step, int):
            if not isinstance(node, list) or not -len(node) <= step < len(node):
                raise PermanentError(f"response has no '{self._describe_path()}'")
            return node[step]
        if not isinstance(node, dict) or step not in node:
            raise PermanentError(f"response has no '{self._describe_path()}'")
        return node[step]

    @staticmethod
    def _read_error_body(exc: urllib.error.HTTPError, limit: int = 400) -> str:
        """Return a bounded snippet of the provider's error body.

        Without this, diagnosing a rejected request means reproducing the call
        outside the adapter, which is how a five-minute fix becomes an hour.
        Bounded on purpose: an error body is provider diagnostics, but it can
        echo part of the request, so it is truncated rather than logged whole.
        """
        try:
            body = exc.read().decode("utf-8", errors="replace").strip()
        except Exception:  # noqa: BLE001 - a body we cannot read is not fatal
            return ""
        collapsed = " ".join(body.split())
        return collapsed[:limit] + ("..." if len(collapsed) > limit else "")

    @staticmethod
    def _classify(exc: urllib.error.HTTPError, detail: str = "") -> Exception:
        suffix = f": {detail}" if detail else ""
        if exc.code in _RETRYABLE:
            return TransientError(f"provider returned {exc.code}{suffix}")
        if exc.code in (403, 451):
            return ContentRejected(f"provider refused the request ({exc.code}){suffix}")
        return PermanentError(f"provider returned {exc.code}{suffix}")

"""The HTTP adapter, driven by a fake opener. No socket is ever opened."""

from __future__ import annotations

import io
import json
import urllib.error
import urllib.request

import pytest

from llm_ports import ContentRejected, Message, PermanentError, Request, Role, TransientError
from llm_ports.adapters import HttpLanguageModel, HttpProviderConfig

CONFIG = HttpProviderConfig(
    endpoint="https://provider.example/v1/chat",
    api_key="test-key-not-a-real-credential",
    model_id="configured-elsewhere",
)


def _request() -> Request:
    return Request(messages=(Message(role=Role.USER, content="hello"),))


class _FakeResponse(io.BytesIO):
    """Minimal stand-in for the context manager urlopen returns.

    Inherits `read(size)` from BytesIO, which is what lets the adapter's
    bounded read be exercised without a network.
    """

    def __enter__(self):
        return self

    def __exit__(self, *exc_info) -> None:
        self.close()


def _opener_returning(body: dict, captured: list | None = None):
    def opener(http_request, timeout=None):
        if captured is not None:
            captured.append(http_request)
        return _FakeResponse(json.dumps(body).encode("utf-8"))

    return opener


def _opener_raising(exc: Exception):
    def opener(http_request, timeout=None):
        raise exc

    return opener


def test_reads_the_text_from_the_configured_path() -> None:
    adapter = HttpLanguageModel(
        CONFIG, opener=_opener_returning({"output": {"text": "the answer"}})
    )

    assert adapter.generate(_request()).text == "the answer"


def test_a_different_shape_is_a_config_change_not_a_code_change() -> None:
    # Same adapter, provider that nests the text elsewhere.
    other = HttpProviderConfig(
        endpoint="https://other.example/v1",
        api_key="k",
        model_id="m",
        response_text_path=("choices", "message"),
    )
    adapter = HttpLanguageModel(
        other, opener=_opener_returning({"choices": {"message": "elsewhere"}})
    )

    assert adapter.generate(_request()).text == "elsewhere"


def test_sends_the_credential_as_a_bearer_token() -> None:
    captured: list = []
    adapter = HttpLanguageModel(
        CONFIG, opener=_opener_returning({"output": {"text": "x"}}, captured)
    )
    adapter.generate(_request())

    sent = captured[0]
    assert sent.get_header("Authorization") == f"Bearer {CONFIG.api_key}"
    assert json.loads(sent.data)["model"] == CONFIG.model_id


def test_reports_usage_using_the_common_field_names() -> None:
    # Defaults follow the widest convention rather than an invented one.
    adapter = HttpLanguageModel(
        CONFIG,
        opener=_opener_returning(
            {
                "output": {"text": "x"},
                "usage": {"prompt_tokens": 11, "completion_tokens": 3},
            }
        ),
    )

    usage = adapter.generate(_request()).usage
    assert (usage.input_tokens, usage.output_tokens) == (11, 3)


def test_usage_field_names_are_configurable() -> None:
    # Found by a live call that reported nothing: these were hardcoded.
    config = HttpProviderConfig(
        endpoint="https://provider.example/v1",
        api_key="k",
        model_id="m",
        usage_input_field="input_tokens",
        usage_output_field="output_tokens",
    )
    adapter = HttpLanguageModel(
        config,
        opener=_opener_returning(
            {"output": {"text": "x"}, "usage": {"input_tokens": 7, "output_tokens": 2}}
        ),
    )

    usage = adapter.generate(_request()).usage
    assert (usage.input_tokens, usage.output_tokens) == (7, 2)


def test_missing_usage_is_not_an_error() -> None:
    adapter = HttpLanguageModel(CONFIG, opener=_opener_returning({"output": {"text": "x"}}))

    usage = adapter.generate(_request()).usage
    assert (usage.input_tokens, usage.output_tokens) == (None, None)


def test_finish_reason_is_read_from_inside_a_choice() -> None:
    # Providers that wrap the answer in a list report the stop reason there.
    config = HttpProviderConfig(
        endpoint="https://provider.example/v1",
        api_key="k",
        model_id="m",
        response_text_path=("choices", 0, "message", "content"),
    )
    adapter = HttpLanguageModel(
        config,
        opener=_opener_returning(
            {"choices": [{"message": {"content": "cut"}, "finish_reason": "length"}]}
        ),
    )

    assert adapter.generate(_request()).finish_reason == "length"


@pytest.mark.parametrize("code", [408, 429, 500, 503])
def test_retryable_status_becomes_transient(code: int) -> None:
    adapter = HttpLanguageModel(
        CONFIG,
        opener=_opener_raising(
            urllib.error.HTTPError(CONFIG.endpoint, code, "", {}, None)
        ),
    )

    with pytest.raises(TransientError):
        adapter.generate(_request())


@pytest.mark.parametrize("code", [400, 401, 404])
def test_client_error_becomes_permanent(code: int) -> None:
    adapter = HttpLanguageModel(
        CONFIG,
        opener=_opener_raising(
            urllib.error.HTTPError(CONFIG.endpoint, code, "", {}, None)
        ),
    )

    with pytest.raises(PermanentError):
        adapter.generate(_request())


def test_policy_refusal_is_its_own_error() -> None:
    # Callers usually want to show this to the user, not log it as a bug.
    adapter = HttpLanguageModel(
        CONFIG,
        opener=_opener_raising(
            urllib.error.HTTPError(CONFIG.endpoint, 403, "", {}, None)
        ),
    )

    with pytest.raises(ContentRejected):
        adapter.generate(_request())


def test_unreachable_provider_is_transient() -> None:
    adapter = HttpLanguageModel(
        CONFIG, opener=_opener_raising(urllib.error.URLError("dns failure"))
    )

    with pytest.raises(TransientError):
        adapter.generate(_request())


def test_missing_text_field_is_permanent() -> None:
    adapter = HttpLanguageModel(CONFIG, opener=_opener_returning({"unexpected": 1}))

    with pytest.raises(PermanentError):
        adapter.generate(_request())


def test_config_refuses_plain_http() -> None:
    with pytest.raises(ValueError):
        HttpProviderConfig(endpoint="http://insecure.example", api_key="k", model_id="m")


def test_config_refuses_an_empty_credential() -> None:
    with pytest.raises(ValueError):
        HttpProviderConfig(endpoint="https://ok.example", api_key="", model_id="m")


# --- Regressions locked in after review -------------------------------------


def test_credential_never_appears_in_repr() -> None:
    # A config object reaches logs and tracebacks more often than anyone
    # expects. A credential printed once is a credential to rotate.
    config = HttpProviderConfig(
        endpoint="https://provider.example/v1",
        api_key="a-secret-that-must-not-be-printed",
        model_id="m",
    )

    assert "a-secret-that-must-not-be-printed" not in repr(config)
    assert "a-secret-that-must-not-be-printed" not in str(config)
    # The rest of the config stays visible, which is what makes it debuggable.
    assert "provider.example" in repr(config)


def test_config_refuses_an_empty_model_id() -> None:
    with pytest.raises(ValueError):
        HttpProviderConfig(endpoint="https://ok.example", api_key="k", model_id="")


def test_redirects_are_refused_so_the_credential_stays_put() -> None:
    # urllib re-sends Authorization to whatever host a redirect names. The
    # default opener must refuse rather than follow.
    from llm_ports.adapters.http_provider import _NoRedirects

    handler = _NoRedirects()
    request = urllib.request.Request("https://provider.example/v1")

    with pytest.raises(urllib.error.HTTPError):
        handler.redirect_request(
            request, None, 302, "Found", {}, "https://attacker.example/collect"
        )


# --- Regressions found by calling a live provider ----------------------------


def test_request_field_names_are_configurable() -> None:
    # A live call rejected the request because the provider names the output
    # budget differently. Making only the response path configurable was an
    # asymmetry; the request body needs the same treatment.
    captured: list = []
    config = HttpProviderConfig(
        endpoint="https://provider.example/v1",
        api_key="k",
        model_id="m",
        max_tokens_field="max_completion_tokens",
        temperature_field="temp",
    )
    adapter = HttpLanguageModel(
        config, opener=_opener_returning({"output": {"text": "x"}}, captured)
    )
    adapter.generate(_request())

    body = json.loads(captured[0].data)
    assert "max_completion_tokens" in body
    assert "temp" in body
    assert "max_tokens" not in body


def test_default_field_names_follow_the_common_convention() -> None:
    captured: list = []
    adapter = HttpLanguageModel(
        CONFIG, opener=_opener_returning({"output": {"text": "x"}}, captured)
    )
    adapter.generate(_request())

    body = json.loads(captured[0].data)
    assert body["max_tokens"] == 512
    assert body["temperature"] == 0.0


def test_error_carries_the_provider_explanation() -> None:
    # Without the body, diagnosing a rejected request means reproducing the
    # call outside the adapter.
    detail = b'{"error": {"message": "Unknown name \\"foo\\": Cannot find field."}}'
    adapter = HttpLanguageModel(
        CONFIG,
        opener=_opener_raising(
            urllib.error.HTTPError(
                CONFIG.endpoint, 400, "", {}, io.BytesIO(detail)
            )
        ),
    )

    with pytest.raises(PermanentError, match="Cannot find field"):
        adapter.generate(_request())


def test_error_detail_is_truncated() -> None:
    # An error body can echo part of the request, so it is bounded.
    adapter = HttpLanguageModel(
        CONFIG,
        opener=_opener_raising(
            urllib.error.HTTPError(
                CONFIG.endpoint, 400, "", {}, io.BytesIO(b"x" * 2000)
            )
        ),
    )

    with pytest.raises(PermanentError) as caught:
        adapter.generate(_request())

    assert len(str(caught.value)) < 500
    assert str(caught.value).endswith("...")


def test_an_unreadable_error_body_is_not_fatal() -> None:
    adapter = HttpLanguageModel(
        CONFIG,
        opener=_opener_raising(
            urllib.error.HTTPError(CONFIG.endpoint, 500, "", {}, None)
        ),
    )

    with pytest.raises(TransientError):
        adapter.generate(_request())


def test_path_can_index_into_arrays() -> None:
    # Found by a live call: most providers wrap the answer in a list, and the
    # unit tests had all used object-only shapes because the same blind spot
    # wrote both the code and the tests.
    config = HttpProviderConfig(
        endpoint="https://provider.example/v1",
        api_key="k",
        model_id="m",
        response_text_path=("choices", 0, "message", "content"),
    )
    adapter = HttpLanguageModel(
        config,
        opener=_opener_returning(
            {"choices": [{"message": {"content": "inside a list"}}]}
        ),
    )

    assert adapter.generate(_request()).text == "inside a list"


def test_index_out_of_range_is_permanent() -> None:
    config = HttpProviderConfig(
        endpoint="https://provider.example/v1",
        api_key="k",
        model_id="m",
        response_text_path=("choices", 3, "text"),
    )
    adapter = HttpLanguageModel(config, opener=_opener_returning({"choices": []}))

    with pytest.raises(PermanentError, match="choices.3.text"):
        adapter.generate(_request())


def test_indexing_something_that_is_not_a_list_is_permanent() -> None:
    config = HttpProviderConfig(
        endpoint="https://provider.example/v1",
        api_key="k",
        model_id="m",
        response_text_path=("choices", 0),
    )
    adapter = HttpLanguageModel(config, opener=_opener_returning({"choices": {}}))

    with pytest.raises(PermanentError):
        adapter.generate(_request())


def test_missing_text_with_a_truncation_reason_is_an_empty_answer() -> None:
    # A live call with a tiny budget returned a message with no content field.
    # That is an empty answer, not a malformed request.
    config = HttpProviderConfig(
        endpoint="https://provider.example/v1",
        api_key="k",
        model_id="m",
        response_text_path=("choices", 0, "message", "content"),
    )
    adapter = HttpLanguageModel(
        config,
        opener=_opener_returning(
            {"choices": [{"message": {}, "finish_reason": "length"}]}
        ),
    )

    response = adapter.generate(_request())
    assert response.text == ""
    assert response.finish_reason == "length"


def test_missing_text_without_a_truncation_reason_is_still_permanent() -> None:
    # Absent a stop reason, an unreadable shape is a real problem.
    adapter = HttpLanguageModel(CONFIG, opener=_opener_returning({"unexpected": 1}))

    with pytest.raises(PermanentError):
        adapter.generate(_request())



def test_an_oversized_body_is_refused_before_it_is_buffered() -> None:
    # `read()` with no argument reads until the peer stops sending. A broken or
    # hostile provider would otherwise exhaust the process.
    config = HttpProviderConfig(
        endpoint="https://provider.example/v1",
        api_key="k",
        model_id="m",
        max_response_bytes=1024,
    )
    huge = json.dumps({"output": {"text": "x" * 5000}}).encode()
    adapter = HttpLanguageModel(config, opener=lambda req, timeout=None: _FakeResponse(huge))

    with pytest.raises(PermanentError, match="exceeds 1024 bytes"):
        adapter.generate(_request())


def test_a_body_exactly_at_the_limit_is_accepted() -> None:
    payload = json.dumps({"output": {"text": "ok"}}).encode()
    config = HttpProviderConfig(
        endpoint="https://provider.example/v1",
        api_key="k",
        model_id="m",
        max_response_bytes=len(payload),
    )
    adapter = HttpLanguageModel(
        config, opener=lambda req, timeout=None: _FakeResponse(payload)
    )

    assert adapter.generate(_request()).text == "ok"


def test_the_ceiling_must_be_positive() -> None:
    with pytest.raises(ValueError):
        HttpProviderConfig(
            endpoint="https://ok.example", api_key="k", model_id="m", max_response_bytes=0
        )

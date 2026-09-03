"""Contract tests against a real provider.

Everything else in this suite verifies the adapter against a stand-in, which
means it verifies our model of a provider rather than a provider. That gap is
not theoretical: the first live call against this adapter found six defects
that the offline suite had passed over, because the same assumptions wrote both
the code and the fakes.

These tests close that gap. They are skipped unless the environment supplies an
endpoint and a credential, so they never block a commit, and they name no
vendor: the provider is entirely a matter of configuration.

    export LLM_CONTRACT_ENDPOINT=https://provider.example/v1/chat/completions
    export LLM_CONTRACT_API_KEY=...
    export LLM_CONTRACT_MODEL=...
    export LLM_CONTRACT_TEXT_PATH=choices.0.message.content
    pytest -m contract

Run them on a schedule, not on every push. They cost money and they fail when
someone else's service is busy, which is information about the provider rather
than about this code.
"""

from __future__ import annotations

import os

import pytest

from llm_ports import Message, Request, Role, TransientError
from llm_ports.adapters import HttpLanguageModel, HttpProviderConfig
from llm_ports.usecases import SummarizeDocument

pytestmark = pytest.mark.contract

_REQUIRED = ("LLM_CONTRACT_ENDPOINT", "LLM_CONTRACT_API_KEY", "LLM_CONTRACT_MODEL")

skip_without_credentials = pytest.mark.skipif(
    not all(os.environ.get(name) for name in _REQUIRED),
    reason="set LLM_CONTRACT_* to run contract tests against a real provider",
)


def _config() -> HttpProviderConfig:
    raw_path = os.environ.get("LLM_CONTRACT_TEXT_PATH", "choices.0.message.content")
    path = tuple(int(step) if step.isdigit() else step for step in raw_path.split("."))
    return HttpProviderConfig(
        endpoint=os.environ["LLM_CONTRACT_ENDPOINT"],
        api_key=os.environ["LLM_CONTRACT_API_KEY"],
        model_id=os.environ["LLM_CONTRACT_MODEL"],
        response_text_path=path,
        max_tokens_field=os.environ.get("LLM_CONTRACT_MAX_TOKENS_FIELD", "max_tokens"),
    )


def _ask(text: str, budget: int = 200) -> Request:
    return Request(
        messages=(
            Message(role=Role.SYSTEM, content="Answer in one short sentence."),
            Message(role=Role.USER, content=text),
        ),
        max_output_tokens=budget,
    )


@skip_without_credentials
def test_the_request_body_is_accepted() -> None:
    """The field names we send are the ones the provider expects.

    The first live call failed here: the output-budget field had a different
    name, which the offline suite could not have detected.
    """
    adapter = HttpLanguageModel(_config())

    try:
        response = adapter.generate(_ask("Say hello."))
    except TransientError as exc:
        pytest.skip(f"provider unavailable: {exc}")

    assert response.text is not None


@skip_without_credentials
def test_the_answer_is_where_the_configured_path_says() -> None:
    """The response path resolves against the real payload shape.

    The second live failure: most providers wrap the answer in a list, and a
    path that only walked objects could not reach it.
    """
    adapter = HttpLanguageModel(_config())

    try:
        response = adapter.generate(_ask("Reply with the single word: ok"))
    except TransientError as exc:
        pytest.skip(f"provider unavailable: {exc}")

    assert response.text.strip(), "the provider returned no text at the configured path"


@skip_without_credentials
def test_usage_is_reported_under_the_configured_field_names() -> None:
    """Token accounting arrives, rather than silently reading as unknown."""
    adapter = HttpLanguageModel(_config())

    try:
        response = adapter.generate(_ask("Say hello."))
    except TransientError as exc:
        pytest.skip(f"provider unavailable: {exc}")

    assert response.usage.input_tokens is not None, "usage field names do not match"


@skip_without_credentials
def test_an_exhausted_budget_is_reported_as_truncation() -> None:
    """A model that runs out of budget must not look like a complete answer.

    This is the defect that mattered most: a one-word summary was returned as a
    success because nothing inspected the stop reason.
    """
    summarize = SummarizeDocument(_config_adapter(), max_attempts=4, backoff_seconds=2.0)

    try:
        result = summarize(
            "A document long enough to need summarising." * 5, max_output_tokens=8
        )
    except TransientError as exc:
        pytest.skip(f"provider unavailable: {exc}")

    assert result.truncated is True


@skip_without_credentials
def test_a_generous_budget_is_not_reported_as_truncation() -> None:
    summarize = SummarizeDocument(_config_adapter(), max_attempts=4, backoff_seconds=2.0)

    try:
        result = summarize("A document long enough to need summarising." * 5, word_limit=60)
    except TransientError as exc:
        pytest.skip(f"provider unavailable: {exc}")

    assert result.truncated is False
    assert result.text.strip()


def _config_adapter() -> HttpLanguageModel:
    return HttpLanguageModel(_config())

"""The use case, exercised end to end without a network."""

from __future__ import annotations

import pytest

from llm_ports import PermanentError, Role, TransientError
from llm_ports.adapters import InMemoryLanguageModel
from llm_ports.usecases import SummarizeDocument


def test_returns_the_model_answer() -> None:
    model = InMemoryLanguageModel(responses=["A short summary."])
    summarize = SummarizeDocument(model)

    result = summarize("A long document about cloud migrations.")

    assert result.text == "A short summary."
    assert result.attempts == 1
    assert model.call_count == 1


def test_sends_the_instruction_before_the_document() -> None:
    model = InMemoryLanguageModel(responses=["ok"])
    SummarizeDocument(model)("the document", word_limit=40)

    sent = model.last_request
    assert sent is not None
    assert sent.messages[0].role is Role.SYSTEM
    assert "40 words" in sent.messages[0].content
    assert sent.messages[1].role is Role.USER
    assert sent.messages[1].content == "the document"


def test_asks_for_deterministic_output() -> None:
    # Summaries should not vary between runs, so temperature is pinned at 0.
    model = InMemoryLanguageModel(responses=["ok"])
    SummarizeDocument(model)("doc")

    assert model.last_request is not None
    assert model.last_request.temperature == 0.0


def test_retries_a_transient_failure_then_succeeds() -> None:
    model = InMemoryLanguageModel(
        responses=[TransientError("rate limited"), "recovered summary"]
    )
    slept: list[float] = []
    summarize = SummarizeDocument(model, backoff_seconds=0.1, sleep=slept.append)

    result = summarize("doc")

    assert result.text == "recovered summary"
    assert result.attempts == 2
    assert slept == [0.1]  # backed off once, and did not really wait


def test_gives_up_after_max_attempts() -> None:
    model = InMemoryLanguageModel(
        responses=[TransientError("boom")] * 3
    )
    summarize = SummarizeDocument(model, max_attempts=3, sleep=lambda _: None)

    with pytest.raises(TransientError):
        summarize("doc")

    assert model.call_count == 3


def test_does_not_retry_a_permanent_failure() -> None:
    # Repeating a malformed request only burns budget.
    model = InMemoryLanguageModel(responses=[PermanentError("bad request")])
    summarize = SummarizeDocument(model, sleep=lambda _: None)

    with pytest.raises(PermanentError):
        summarize("doc")

    assert model.call_count == 1


def test_rejects_an_empty_document() -> None:
    summarize = SummarizeDocument(InMemoryLanguageModel())

    with pytest.raises(ValueError):
        summarize("   ")


def test_answer_can_depend_on_the_input() -> None:
    model = InMemoryLanguageModel(
        rule=lambda req: f"{len(req.messages)} messages received"
    )

    assert SummarizeDocument(model)("doc").text == "2 messages received"


def test_truncation_is_reported_instead_of_hidden() -> None:
    # A live call returned a one-word summary and reported success, because
    # the model spent the output budget reasoning. A truncated summary is a
    # wrong answer, and a silent one is worse than an error.
    from llm_ports.domain import Response

    class _Truncating:
        def generate(self, request):  # type: ignore[no-untyped-def]
            return Response(text="La", finish_reason="length")

    result = SummarizeDocument(_Truncating())("a long document")

    assert result.truncated is True


def test_a_complete_answer_is_not_marked_truncated() -> None:
    model = InMemoryLanguageModel(responses=["A complete summary."])

    assert SummarizeDocument(model)("doc").truncated is False


def test_budget_is_not_derived_from_the_word_limit() -> None:
    # A contract test proved no multiplier of the word count is ever right:
    # reasoning consumes an unrelated and variable share of the budget.
    model = InMemoryLanguageModel(responses=["ok"] * 2)
    SummarizeDocument(model)("doc", word_limit=10)
    small = model.last_request
    SummarizeDocument(model)("doc", word_limit=500)
    large = model.last_request

    assert small is not None and large is not None
    assert small.max_output_tokens == large.max_output_tokens


def test_the_caller_can_cap_the_budget_deliberately() -> None:
    model = InMemoryLanguageModel(responses=["ok"])
    SummarizeDocument(model)("doc", max_output_tokens=64)

    assert model.last_request is not None
    assert model.last_request.max_output_tokens == 64

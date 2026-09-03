"""Domain invariants. Cheap to check, and they stop bad requests early."""

from __future__ import annotations

import pytest

from llm_ports import Message, Request, Role


def test_message_rejects_empty_content() -> None:
    with pytest.raises(ValueError):
        Message(role=Role.USER, content="  ")


def test_request_needs_at_least_one_message() -> None:
    with pytest.raises(ValueError):
        Request(messages=())


@pytest.mark.parametrize("temperature", [-0.1, 2.1])
def test_request_rejects_temperature_out_of_range(temperature: float) -> None:
    with pytest.raises(ValueError):
        Request(
            messages=(Message(role=Role.USER, content="hi"),),
            temperature=temperature,
        )


def test_request_rejects_non_positive_output_budget() -> None:
    with pytest.raises(ValueError):
        Request(messages=(Message(role=Role.USER, content="hi"),), max_output_tokens=0)

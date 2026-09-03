"""Domain types for language model interaction.

These types are deliberately free of any provider vocabulary. Nothing here
names a vendor, a model or a wire format, so the domain does not change when
the provider does.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum


class Role(str, Enum):
    """Who produced a message."""

    SYSTEM = "system"
    USER = "user"
    ASSISTANT = "assistant"


@dataclass(frozen=True)
class Message:
    """A single turn in a conversation."""

    role: Role
    content: str

    def __post_init__(self) -> None:
        if not self.content.strip():
            raise ValueError("message content must not be empty")


@dataclass(frozen=True)
class Request:
    """What the application asks for, independent of any provider.

    `max_output_tokens` and `temperature` are expressed as intent, not as the
    parameter names of a particular API. Adapters translate them.
    """

    messages: tuple[Message, ...]
    max_output_tokens: int = 512
    temperature: float = 0.0

    def __post_init__(self) -> None:
        if not self.messages:
            raise ValueError("a request needs at least one message")
        if self.max_output_tokens <= 0:
            raise ValueError("max_output_tokens must be positive")
        if not 0.0 <= self.temperature <= 2.0:
            raise ValueError("temperature must be between 0.0 and 2.0")


@dataclass(frozen=True)
class Usage:
    """Token accounting, when the provider reports it.

    Kept optional on purpose: a provider that does not report usage should not
    force the domain to invent numbers.
    """

    input_tokens: int | None = None
    output_tokens: int | None = None


@dataclass(frozen=True)
class Response:
    """What the application gets back."""

    text: str
    usage: Usage = field(default_factory=Usage)
    finish_reason: str | None = None

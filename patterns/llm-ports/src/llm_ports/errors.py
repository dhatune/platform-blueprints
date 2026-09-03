"""Error taxonomy for language model calls.

The split that matters to a caller is not which provider failed but whether
retrying can help. Adapters map provider-specific failures onto these.
"""

from __future__ import annotations


class LanguageModelError(Exception):
    """Base class for every failure raised by an adapter."""


class TransientError(LanguageModelError):
    """The call may succeed if retried: timeout, rate limit, 5xx."""


class PermanentError(LanguageModelError):
    """Retrying will not help: malformed request, auth failure, 4xx."""


class ContentRejected(PermanentError):
    """The provider refused to answer for policy reasons.

    Separated from PermanentError because callers often want to surface this
    to the user rather than treat it as a bug.
    """

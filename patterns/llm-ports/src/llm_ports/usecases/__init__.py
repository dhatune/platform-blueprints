"""Application use cases. They depend on ports, never on adapters."""

from .summarize import SummarizeDocument, Summary

__all__ = ["SummarizeDocument", "Summary"]

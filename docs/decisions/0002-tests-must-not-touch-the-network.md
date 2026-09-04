# 2. Tests must not touch the network

**Date:** 2026-09-03
**Status:** Accepted, revised the same day (see Revision)

## Context

Tests that call a real language model API are slow, cost money per run, fail
when the provider degrades, and return different text on different runs. Teams
respond by mocking the SDK, which verifies the mock rather than the system, or
by skipping the tests, which verifies nothing.

## Decision

No test on the commit path performs network I/O.

The in-memory adapter is a first-class implementation of the port, not a test
double created per test. It supports a scripted queue, a rule based on the
request, and a default answer, and it can raise the same error types a real
adapter raises.

The HTTP adapter takes its opener as a constructor argument, so its own tests
drive it with a fake and never open a socket.

## Alternatives considered

**Record and replay real responses.** Realistic, and it drifts. Cassettes go
stale and their failure mode is a passing test against last year's API.

**Mock the SDK per test.** Couples every test to the shape of a dependency that
is expected to change, which is exactly what the port exists to avoid.

## Consequences

The suite runs in under a tenth of a second and is deterministic, so it can run
on every commit without anyone weighing the cost.

An offline suite verifies logic. It cannot verify assumptions, because the
stand-ins answer the way their author expected a provider to answer. When the
same person writes the code and the fakes, both carry the same blind spots and
the suite confirms them.

---

## Revision

The first version of this decision closed by saying contract drift "is not
caught" and that leaving it uncovered was a deliberate scope decision.

That was wrong, and the first live call proved it within the hour.

Forty-eight passing offline tests coexisted with **seven defects**, every one of
them invisible to a stand-in:

1. Request field names were hardcoded while the response path was configurable.
2. Errors discarded the provider's explanation, so diagnosis meant leaving the
   adapter.
3. The response path walked objects only; most providers wrap the answer in an
   array.
4. A truncated answer was returned as a success, because nothing inspected the
   stop reason.
5. Token usage was read under assumed field names and silently came back empty.
6. An empty answer caused by an exhausted budget was classified as a malformed
   request.
7. The output budget was derived from the requested word count. No multiplier of
   a word count can predict how much budget a model spends reasoning before it
   answers. The idea was wrong, not the number, and it survived two rounds of
   tuning before a contract test settled it.

Defects 1, 3, 5 and 6 are one mistake repeated: shapes were assumed where they
should have been configured. The adapter promised to absorb differences between
providers and only honoured that promise in the direction its author thought to
look.

**Amended decision.** The commit path stays offline, unchanged. A separate
contract suite runs against a real provider, marked `contract` and excluded by
default. It is skipped when no credentials are present, so it never blocks a
commit, and it names no vendor: the provider is entirely configuration.

Each contract test states in its docstring which of the seven defects it exists
to prevent. They are not generic checks; they are the memory of what already
broke.

```bash
pytest              # 49 tests, no sockets opened
pytest -m contract  # against the configured provider
```

Run the contract suite on a schedule and before a release, not on every push. It
costs money and it fails when someone else's service is busy, which is
information about the provider rather than about this code.

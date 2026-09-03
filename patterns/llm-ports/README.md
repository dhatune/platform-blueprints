# LLM Ports and Adapters

Provider-agnostic access to language models.

## The problem

You wire a language model into your product. Six months later the provider
changes its pricing, deprecates the model, or your compliance team asks whether
the data can stay in-country. Now you find out how much of your codebase knows
the provider's name.

The other half of the problem is testing. If your tests call the real API they
are slow, they cost money, they fail when the provider has a bad day, and they
give different answers on different runs. So most teams mock the SDK, which
tests the mock rather than the system.

## The approach

The application depends on one protocol:

```python
class LanguageModelPort(Protocol):
    def generate(self, request: Request) -> Response: ...
```

Everything else is an adapter. Two ship here:

- **`HttpLanguageModel`** talks to any provider exposing a chat-style JSON
  endpoint. The endpoint, credential, model identifier and even the JSON path
  where the answer lives are configuration. A different provider is a different
  config, not different code.
- **`InMemoryLanguageModel`** is a full implementation whose backing store is a
  list. It is not a mock: tests exercise the same code path production uses,
  minus the network.

The use case in `usecases/summarize.py` imports neither. It receives a port.

## What this buys

**Substitution is a config change.** The only file that names a provider is the
one that builds the adapter at startup.

**Tests run offline and deterministically.**

```
$ pytest
29 passed in 0.08s
```

No sockets, no credentials, no flakiness, no bill.

**Failures are classified by what the caller can do about them.** Adapters map
provider errors onto `TransientError` (retry may help) and `PermanentError` (it
will not). The retry logic in the use case is three lines and correct, because
it never retries a malformed request.

**Policy refusals are their own type.** `ContentRejected` is separated because
callers usually want to show it to the user rather than log it as a defect.

## Running it

```bash
cd patterns/llm-ports
pip install -e ".[dev]"
pytest
```

## Verification

```bash
pytest              # 49 tests, no sockets opened
mypy --strict src   # no issues
pytest -m contract  # against a real provider, when credentials are present
```

`--strict` is the claim worth making. The default mode does not even inspect the
bodies of unannotated functions, so passing it means little. Strict mode demands
that every parameter and return is annotated, including the injected seams — the
clock and the HTTP opener — which are exactly the places a codebase tends to
leave untyped.

## What the first live call found

The offline suite is fast, deterministic and green. It also passed while seven
defects sat in the adapter, because a stand-in answers the way its author
expected a provider to answer. The same assumptions wrote the code and the
fakes, so the tests confirmed the mistake instead of catching it.

The first call to a real provider found all seven:

| # | Defect |
|---|---|
| 1 | Request field names hardcoded while the response path was configurable |
| 2 | Errors discarded the provider's explanation |
| 3 | The response path walked objects only; most providers wrap the answer in an array |
| 4 | A truncated answer was returned as a success |
| 5 | Token usage read under assumed field names, silently empty |
| 6 | An empty answer from an exhausted budget classified as a malformed request |
| 7 | The output budget derived from the requested word count |

Four of them — 1, 3, 5 and 6 — are the same mistake repeated: shapes assumed
where they should have been configured. The adapter promised to absorb
differences between providers and honoured that promise only in the direction
its author thought to look.

Number 7 is the one worth keeping. A model that reasons before answering spends
an unknown and variable share of the budget thinking, so no multiplier of a word
count predicts it. The idea was wrong, not the number, and it survived two
rounds of tuning before a contract test settled it. The word limit is now a soft
instruction to the model; the token budget is a deliberate cap the caller may
set, and `Summary.truncated` reports when it was not enough.

Number 4 was the most dangerous. A truncated summary is a wrong answer, and
returning it as a success is worse than failing.

Every contract test states in its docstring which defect it exists to prevent.
They are not generic checks; they are the memory of what already broke.

The reasoning is in
[ADR 2](../../docs/decisions/0002-tests-must-not-touch-the-network.md), whose
first version claimed this gap was out of scope. It was not.

## Where this pattern stops working

A single port covers `generate()` well. It strains once you need tool use,
schema-constrained output or streaming, and those three do not strain it
equally.

| Capability | Portability | What leaks |
|---|---|---|
| Structured output | Good | Schema dialect subsets differ between providers |
| Tool use | Fair | Parallel calls, result reinjection, forced-choice semantics |
| Streaming | Poor | Changes the calling shape, not just the payload |

Streaming is the hard one, and not for the obvious reason: `generate() -> Response`
becomes an iterator, and that propagates into every caller.

The answer is not one widening interface. It is segregated ports, so an
application that only summarises pays for nothing else. And when a product truly
depends on one provider's deep tool semantics, the honest move is to declare the
lock-in rather than hide it behind an abstraction that leaks.

The reasoning is in [ADR 3](../../docs/decisions/0003-segregated-ports-for-advanced-capabilities.md).
Only `LanguageModelPort` is implemented here; the rest is documented, not shipped.

## A limit worth knowing about: 429 is two different failures

The adapter classifies `429 Too Many Requests` as transient and the use case
retries it. That is right for rate limiting, where waiting is exactly the remedy.

It is wrong for an exhausted quota, and the two share a status code. Retrying a
quota failure spends calls against an allowance that no longer exists, so the
retry policy makes the situation worse rather than better.

This is not hypothetical. While these contract tests were being written, a key
moved from rate limiting to quota exhaustion and the retry loop kept going,
consuming what was left. Telling the two apart requires reading the provider's
error message, which is provider-specific by definition — the sort of knowledge
a port is meant to keep out.

Two honest options, neither free:

- Treat `429` as permanent and let the caller decide. Safe, and it gives up
  retrying the case where retrying is the correct answer.
- Inspect the message in the adapter. Correct, and it puts vendor-specific
  string matching in the layer built to avoid exactly that.

This implementation takes neither and documents the ambiguity instead, because
the right answer depends on whether your budget or your latency hurts more. What
it does not do is pretend the distinction is not there.

## Also deliberately not here

No retry-with-jitter, no circuit breaker, no token counting, no caching, no
async, and no total-operation timeout — the 30-second budget is per request, so
retries extend the wall clock. All of them belong in production and all of them
would obscure the one idea this is meant to show. The seam is the point; what
you hang off it is context-dependent.

## Layout

```
src/llm_ports/
  domain.py            types with no provider vocabulary
  ports.py             the protocol the application depends on
  errors.py            transient / permanent / policy
  adapters/
    in_memory.py       the reason tests need no network
    http_provider.py   any chat-style JSON endpoint
  usecases/
    summarize.py       depends on the port, imports no adapter
tests/                 29 tests, none of them touch a network
```

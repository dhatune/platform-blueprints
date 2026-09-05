# 3. Segregate the ports instead of widening one

**Date:** 2026-09-03
**Status:** Accepted

## Context

ADR 1 established a single `LanguageModelPort` with one method. That covers the
common case well, and it is honest about being a lowest common denominator.

It is worth naming precisely where that ceiling is, because a reviewer will find
it and the answer should already be here. Three capabilities strain a shared
port, and they do not strain it equally.

**Structured output (JSON Schema).** The most portable of the three. Providers
converged: declare a schema, receive conforming JSON. What leaks is the schema
dialect, each provider supports a different subset, and constructs like
`oneOf` or `$ref` are unevenly honoured. Small, containable leak.

**Tool use.** Middling. The overall shape converged: declare tools with a name
and a parameter schema, the model requests a call, the caller executes it and
feeds the result back. What differs is edge semantics, whether parallel calls
are allowed, how a result is reinjected into the conversation, what "force this
tool" actually guarantees. Abstractable with effort; leaks at the edges.

**Streaming.** The genuinely hard one, and not for the obvious reason. The
difficulty is not that tokens arrive differently. It is that the shape of the
API changes: `generate() -> Response` becomes an iterator, and that propagates
into every use case, which can no longer be a function that returns a value.
On top of that the event models diverge in substance: partial tool calls,
deltas versus cumulative text, where usage is reported, how a mid-stream error
surfaces.

Widening one port to cover all four cases produces the worst outcome: an
interface where most methods are unsupported by most adapters, and where callers
must ask what the adapter can do before calling it. That is a leaky abstraction
wearing the costume of a clean one.

## Decision

Segregate the ports. Each capability is its own protocol, and an application
depends only on the ones it uses.

```
LanguageModelPort      generate()        the common case
StructuredOutputPort   generate_typed()  schema-constrained output
ToolUsePort            converse()        tool declaration and result feedback
StreamingPort          stream()          incremental output
```

An application that summarizes documents depends on the first alone and pays
nothing for the other three. An application that needs tools depends on the
third and accepts, explicitly, that substitutable providers are fewer there and
the leak is wider.

The abstraction gets narrower as the capability gets more provider-specific,
which is the opposite of what a single widening interface does.

## Alternatives considered

**One port with optional capabilities.** Callers would have to interrogate the
adapter before using it. That turns a compile-time contract into a runtime
question and spreads provider awareness back through the application: the exact
thing the port exists to prevent.

**Adopt a multi-provider library that already covers all four.** A sound choice
when the surface area is large. It trades one dependency for another and shapes
your domain around someone else's abstraction, which is a real cost when their
priorities and yours diverge.

**Accept vendor lock-in deliberately.** For a product whose value depends on the
deep tool-use semantics of one provider, this is the honest answer. Declaring
the dependency as a decision is better engineering than hiding it behind an
abstraction that leaks. A port that lies is worse than no port.

## Consequences

The common case stays clean and the hard cases stay honest about their cost.

Four protocols is more surface than one. Adapters that support several
capabilities implement several protocols, and the composition root wires more
than one object.

Streaming remains partly outside the abstraction. Because it changes the calling
shape rather than only the payload, an application that streams will look
different from one that does not, regardless of how the port is drawn. This ADR
does not claim to fix that; it claims the seam should not pretend otherwise.

None of the segregated ports beyond `LanguageModelPort` are implemented in this
repository yet. Publishing the reasoning before the code is deliberate: the
decision is the part that transfers, and shipping four half-built protocols to
look complete would contradict ADR 2's stance on finished work.

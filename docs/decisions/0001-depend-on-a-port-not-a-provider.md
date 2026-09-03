# 1. Depend on a port, not on a provider

**Date:** 2026-09-03
**Status:** Accepted

## Context

Language model providers change faster than the products built on them. Pricing
moves, models are deprecated on months of notice, and data residency rules can
force a switch with no notice at all.

The default path is to import the provider SDK where it is needed. It is the
fastest way to a working feature and the reason a later migration touches
dozens of files.

## Decision

The application depends on a `LanguageModelPort` protocol. Providers are
implemented as adapters that satisfy it. Domain types carry no provider
vocabulary: no model identifiers, no wire formats, no SDK objects.

Exactly one place in the system names a provider — the composition root that
builds the adapter at startup.

## Alternatives considered

**Import the SDK directly.** Fastest to write. Rejected because the cost is paid
later, all at once, under time pressure.

**Use a multi-provider abstraction library.** Solves the same problem and adds a
dependency that must itself be tracked, plus an abstraction shaped by someone
else's requirements. Reasonable choice for a large surface area; overkill for
the handful of calls most products actually make.

## Consequences

Swapping a provider is a new adapter and a configuration change.

The port is a lowest common denominator. Provider-specific features are either
absent or leak through, and leaking them defeats the purpose. This is the real
cost: you trade some capability for the ability to move.

Every adapter must map its failures onto the shared error taxonomy. An adapter
that lets a provider exception escape breaks the contract silently.

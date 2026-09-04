# 20. A managed application firewall in front of anything public

**Date:** 2026-09-04
**Status:** Accepted

## Context

A service exposed to the internet receives traffic that has nothing to do with
its users within minutes of the address resolving. Most of it is undirected:
scanners walking address ranges, probes for well-known paths, attempts at
whatever was disclosed last month.

Application code can defend against this and mostly does. The argument for a
layer in front is not that the application is careless; it is about what
arrives before the application has a chance.

Three things it buys. Requests matching known attack shapes are dropped before
reaching a process, which matters most for a vulnerability disclosed in a
dependency that has not been patched yet — the window between disclosure and
deployment is exactly when this earns its cost. Volume can be limited per
source, so one client cannot exhaust a service for everyone. And requests are
recorded at the edge, giving a record of what was attempted rather than only
what succeeded.

What it does not buy is safety. A managed rule set stops recognisable shapes; it
does not stop a request that is well-formed and wrong, which is what an attack
on business logic looks like.

## Decision

Anything reachable from the internet sits behind the platform's managed
application firewall, with the maintained rule set enabled and per-source rate
limiting configured.

It starts in a mode that records what it would have blocked without blocking
it, and is switched to enforcing after that record has been read. A rule set
turned straight to enforcing blocks legitimate traffic that nobody predicted,
and the first report is a support ticket rather than a log line.

Rules are not written by hand except to allow something the maintained set gets
wrong. A local rule set becomes a second application to maintain, with no tests
and one author.

## Alternatives considered

**Rely on the application.** Defensible for a small, well-understood service.
Rejected because it offers nothing during the window between a dependency's
vulnerability being disclosed and the fix being deployed, which is the case
this exists for.

**Run an application firewall as a component.** More control and more
portability. Rejected because it is a component in the request path that has to
be scaled, updated and kept available, and its rule set has to be maintained by
somebody who is now doing that instead of their job.

**Restrict by address instead.** Works where the audience is known, and is a
different decision covered by ADR 16. It does not apply to anything genuinely
public.

## Consequences

It costs per request and per rule, continuously, and the value is invisible when
it is working. This will be questioned in every cost review, and the honest
answer is that the alternative is unmeasurable rather than free.

False positives land on real users, and the first sign is usually a complaint
rather than an alert. Someone has to own the exceptions, and exceptions
accumulate: each one is a hole with a reason that outlives the reason.

And the log of what was blocked is only worth having if it is read. Turning this
on and never looking produces defence without information, which is half of what
was paid for.

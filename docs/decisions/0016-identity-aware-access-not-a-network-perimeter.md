# 16. Internal tools are protected by identity, not by network position

**Date:** 2026-09-04
**Status:** Accepted

## Context

Internal tools, dashboards, admin panels, workflow builders, need to be
reachable by a handful of people and by nobody else. The traditional answer is
network position: a virtual private network, or an address allowlist, so that
being on the inside is what grants access.

That answer has aged badly. It authenticates a network path rather than a
person, so anything on the inside reaches everything on the inside, including
a compromised laptop and a workload that was never meant to make that call. It
also has a running cost and an operational one: the connection is a thing
people install, that breaks, and that becomes the reason a tool is unreachable
from a phone at the wrong moment.

The alternative is a proxy that authenticates the person at the edge and passes
identity to the application. Every request is checked, from anywhere, and
membership is the control rather than location.

The reason this was often rejected was cost and complexity: another component
to run and secure. On this platform that component is provided and carries no
charge of its own, which removes most of the argument against it. What is
charged is the load balancer it sits in front of, which an externally reachable
service needs regardless.

## Decision

Internal tools are published through an identity-aware proxy and are otherwise
unreachable. Access is a group membership, checked on every request. There is
no address allowlist and no private network to join.

Webhook endpoints called by external systems cannot authenticate this way and
are the exception. They are separated at the routing layer so the exception
applies to one path rather than to the whole service, and each one authenticates
its caller itself, see ADR 9.

## Alternatives considered

**A private network.** Familiar, and genuinely necessary for protocols that are
not HTTP. Rejected for web tools because it grants by location, and because the
failure mode is people bypassing it under pressure.

**An address allowlist.** Cheap and better than nothing. Rejected as a primary
control because a home address changes, so the list is edited under pressure by
someone who needs access now, and lists edited that way are widened and not
narrowed afterwards.

**Authentication in each application.** What most tools offer natively. Rejected
because it is only as good as the weakest application, and because
administering accounts in six tools is how the matrix in ADR 15 stops matching
reality.

## Consequences

The proxy becomes a dependency for reaching anything internal. When it is
misconfigured, everything is unreachable at once. That concentration is the
price of removing the network perimeter.

An application behind it still sees a request. If it trusts an identity header
without verifying where it came from, then anything able to reach it directly
can claim to be anybody. Restricting the application to accept traffic only
from the proxy is part of the decision, not an optimisation.

And it applies to HTTP. Databases, administrative shells and anything else
still need their own answer; this decision does not cover them and should not
be read as if it does.

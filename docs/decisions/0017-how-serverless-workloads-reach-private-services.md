# 17. How a serverless workload reaches a private service

**Date:** 2026-09-04
**Status:** Accepted

## Context

A managed runtime has no network of its own. When it needs to reach something
private: a database on an internal address, a service in another network, an
endpoint on-premises: a path has to be built, and the platform offers several
that are easy to confuse because they all end with traffic arriving.

They differ in what they cost and in which direction they work.

One approach places instances in the network on the workload's behalf, forming
a bridge it routes through. Those instances are billed while they exist,
whether traffic flows or not, and they are capacity that has to be sized: too
small throttles, too large is paid for continuously. It is also a component
that can be unhealthy independently of both sides.

A newer approach attaches the workload to the network directly, with no
instances in between. Less to pay for, less to size, less to fail, and it is
the right default for the common case, which is a workload reaching a database
in a network the same organization controls.

A third approach is a private endpoint for a service, which is a different
problem rather than a cheaper solution to the same one. It exposes or consumes
a *service* privately, including across organizations, and gives the consumer
an address inside their own network. It is what to reach for when the far side
is not yours, or when what is being connected is a published service rather
than a subnet.

Choosing by which is cheapest produces the wrong answer, because they are not
substitutes.

## Decision

A workload reaching a private address in a network this organization controls
attaches to that network directly. No bridge instances are provisioned for
that case.

A private endpoint is used when the far side is a published service rather than
a network: a managed offering, another organization's service, or something
this side should not be able to reach beyond the one endpoint.

The instance-based bridge is used only where the platform still requires it,
and its presence is recorded with the reason, because it is a running cost that
survives whoever added it.

## Alternatives considered

**Route everything through the bridge because it is familiar.** It works and it
is what most existing configurations do. Rejected because it is a per-hour
charge and a component to keep healthy, for something the platform now does
without either.

**Make the private service publicly reachable and restrict by address.** Removes
the problem by moving it. Rejected for the same reason ADR 16 rejects address
allowlists: it grants by location, and it puts a database on the internet with
a rule as the only thing in front of it.

## Consequences

Attaching directly means egress leaves through the network, so whatever
controls that network applies: including the absence of an outbound gateway,
which turns "the workload cannot reach the internet" into a surprise at the
worst time. Deciding what is allowed out is part of this, not separate.

Private endpoints multiply. Each one is an address, a rule and a name to
resolve, and an estate with many of them has built a second network that nobody
drew. They are worth counting.

This decision follows the platform's capabilities and will need revisiting.
The instance-based bridge existed because the direct attachment did not; what
is written here as the exception was the only option not long ago.

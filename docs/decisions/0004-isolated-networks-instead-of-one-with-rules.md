# 4. Separate networks per environment, not one network with rules

**Date:** 2026-09-03
**Status:** Accepted

## Context

Production and development workloads must not reach each other. There are two
ways to arrange that on a cloud network, and they differ in what has to hold
true for the isolation to survive.

The common arrangement is one VPC split into subnets, with firewall rules
denying traffic between them. It is cheaper, it keeps addressing in one place,
and shared services can be reached from both sides without duplication.

Its isolation is enforced by policy. A route exists between the two ranges; a
rule declines to use it.

## Decision

Each environment gets its own VPC in the Shared VPC host project. The networks
are not peered and share no routes. There is no path between production and
development to permit or deny.

Firewall rules scope ingress to the subnet's own CIDR, not to the RFC1918
space, so a network added later cannot reach an existing one by default.

Each network has its own private DNS zone, so a name resolved in one
environment cannot resolve to an address in the other.

## Alternatives considered

**One VPC, separate subnets, deny rules between them.** The default choice, and
adequate for many teams. Rejected because the property being protected — that
development cannot reach production — depends on a rule staying correct through
every future edit, and rules are edited under time pressure by people who do
not know why the rule is there.

**VPC peering between the two networks.** Gives the cost advantage of sharing
while nominally keeping the networks distinct. Rejected for the same reason:
peering creates the route, and the isolation returns to being a matter of
policy.

## Consequences

The isolation is structural. Reaching production from development requires
building a connection that does not exist, which is a visible act rather than
an editing mistake.

The cost is real and recurring: anything shared between environments has to be
built twice. A bastion, a monitoring agent, a private registry endpoint. Teams
that expect to share heavily between environments will find this expensive and
should weigh it honestly rather than adopt it because it sounds safer.

Addressing must be planned so the ranges never overlap, in case the two are
ever deliberately connected.

Cloud NAT, if it becomes necessary, is also duplicated. That is the same
trade-off, and it is the reason the baseline omits it entirely until a workload
demands it.

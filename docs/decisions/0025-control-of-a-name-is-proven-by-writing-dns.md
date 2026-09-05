# 25. Control of a name is proven by writing DNS, not by answering on it

**Date:** 2026-09-05
**Status:** Accepted

## Context

A public certificate authority issues a certificate only after the requester
proves control of the name. There are two ordinary ways to do that and they
fail in different places.

Answering a request on the name itself is the obvious one. It requires the name
to already resolve to this cluster and the entry point to already be serving
traffic. On a first deployment neither is true, and the two objects wait on
each other: the entry point is not ready until it has a certificate, and the
certificate is not issued until the entry point answers.

That deadlock is silent. Both objects report that they are waiting, which is
what they would report if they were merely slow, so the state is
indistinguishable from progress. It is resolved by someone recognizing the
shape, which means it costs an afternoon the first time and nothing after that.

Writing a record proves the same fact with no ordering at all. It works before
anything is reachable, and it is the only option for a name that is never
publicly exposed, where answering on the name is not merely awkward but
impossible.

## Decision

Certificates are obtained through the DNS challenge, for every name, including
the ones that are publicly reachable and could have used the other method.

One mechanism rather than two. A deployment that is public today and internal
tomorrow does not change how its certificate is issued, and nobody has to know
which kind of name they are holding.

## Alternatives considered

**Answer on the name.** Needs no DNS permission at all, which is a real
advantage and the reason it is the common default. Rejected because it
deadlocks on first deployment, cannot serve a private name, and because
choosing per name means two mechanisms to understand and one of them is only
exercised rarely.

**Issue certificates by hand.** No permission and no controller. Rejected
because renewal becomes a calendar entry. The certificate expires around ninety
days out, long after whoever created it has moved on, and the failure is total
and public.

**Terminate on a platform-managed certificate instead.** The platform issues
and renews it, and nothing in the cluster holds any DNS permission. A good
answer where every name is public and lives in the same platform. Rejected here
because it does not cover private names and ties the mechanism to one provider,
which ADR 1 argues against in a different context and the reasoning carries.

## Consequences

The issuer needs permission to write into the zone. That is the strongest
permission in this design, and it is granted to a controller rather than to a
person. It is the same permission the record publisher already holds, so the
two share one identity rather than doubling the exposure, and that identity is
assumed through the cluster's workload identity pool and holds no key. ADR 5.

Renewal is not observed in any environment that does not outlive it. It happens
around sixty days in, and a lab, a demonstration or a proof of concept is gone
well before then. The failure mode this creates is specific: a DNS permission
quietly revoked or a zone moved between projects is invisible for two months
and then presents as an expired certificate on a working service.

And the account key is created once and is not backed up unless someone decides
to. Losing it does not invalidate what was already issued. It loses the rate
limit history and the ability to revoke as that account, which is the kind of
cost that is discovered at the worst time.

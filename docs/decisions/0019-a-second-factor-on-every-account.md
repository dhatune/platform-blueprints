# 19. A second factor on every account, not only the privileged ones

**Date:** 2026-09-04
**Status:** Accepted

## Context

Second factors are usually rolled out by importance: administrators first, then
finance, then whoever else seems to warrant it. The reasoning is that effort
should follow risk, and it is wrong about where the risk is.

The way in is rarely the administrator. It is an ordinary account whose owner
reused a password that appeared in someone else's breach. That account is not
interesting on its own, which is exactly why it was left on one factor, and it
does not need to be interesting, because it only has to be a foothold. From
inside, the attacker reads what that person can read, and asks colleagues for
things using their name.

A partial rollout also produces the worst property of all: it is not knowable
who is covered. "Administrators have it" is a statement about a list that was
correct when it was made.

The counter-argument is friction, and it is real. It is also spent once per
person rather than once per login on any modern implementation.

## Decision

Every account carries a second factor, with no exemptions by role or seniority.

Where the second factor lives is the identity provider's problem, not each
application's. An application that maintains its own accounts is the exception
to be removed rather than a place to configure this separately, see ADR 15.

Service accounts and automation are outside this and are covered by not having
passwords at all, per ADR 5.

## Alternatives considered

**Privileged accounts only.** The common rollout. Rejected because the initial
foothold is usually not privileged, and because coverage becomes unknowable.

**A single sign-on provider with no second factor**, on the argument that
centralising is the win. Rejected because it centralizes the target: one
password now opens everything rather than one thing.

**Codes sent as text messages.** Better than nothing and widely accepted.
Rejected as the standard where the platform offers stronger options, because
the delivery channel can be taken over by someone who talks a phone company
into it. Kept as a fallback for people who cannot use anything else, and
recorded as an exception rather than a setting.

## Consequences

There will be lockouts, and the recovery path is the part that gets designed
badly under pressure. A recovery flow weaker than the factor it recovers is the
factor's real strength, this needs deciding before the first person is locked
out, not during.

Shared accounts break. That is a benefit disguised as a cost: a shared login
was already an unattributable action, and this forces the conversation.

And a second factor authenticates a login, not a session. A stolen session
token is unaffected by any of this, which is why session lifetime and revocation
are a separate decision and not one this makes for you.

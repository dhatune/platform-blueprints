# 11. A constraint is not a role

**Date:** 2026-09-03
**Status:** Accepted

## Context

Almost everything in a landing zone is a grant. Someone is given a role, and
the role lets them do something. The property that matters about a grant is
that anyone who can grant roles can grant a different one — including to
themselves, if they hold the right role.

This makes most of a landing zone's security a convention. It holds because
people follow it, and it is reviewed by other people, and it survives exactly
as long as both of those keep happening. Under pressure, at the end of a long
incident, at the moment when the deployment has to go out, the convention is
what gives way. Correctly, from the point of view of the person giving way:
the alternative is a system that stays broken.

A policy constraint is the other kind of control. It is a limit rather than a
permission, applied above the project, and it cannot be removed by someone with
full rights inside that project. It changes what is possible rather than what
is allowed.

## Decision

Decisions that must survive their own inconvenience are expressed as
constraints, not as conventions or roles. In particular: no service account
keys, no identities from outside the organisation in any policy, no external
addresses on machines, no public database addresses, no public buckets.

Constraints are applied before access is granted. A grant made while the
constraints were absent was never checked against them, and applying them later
does not revoke it.

Where a constraint has to be relaxed, the exception is scoped to the smallest
folder that needs it and recorded as configuration with a reason. An exception
that lives as a change somebody once made in a console is not revisited,
because nothing points at it.

## Alternatives considered

**Detective controls: allow the action, alert on it.** Necessary regardless, and
the right answer for anything that cannot be prevented without breaking
legitimate work. It was rejected as the primary mechanism for these particular
decisions because an alert arrives after the key exists, and a key that existed
for an hour must be treated as compromised.

**Policy enforced in the deployment pipeline**, refusing changes that violate
the rules. Valuable, and it gives far better error messages than a platform
constraint does. It was rejected as sufficient on its own because it only sees
changes that go through the pipeline, and the actions worth preventing are
precisely the ones taken outside it at three in the morning.

## Consequences

Constraints break things, and the error messages rarely mention policy. A
managed build that suddenly fails on permissions it used to have is the usual
first encounter, and the cause is not visible from the error. Anyone operating
under these constraints needs to know they exist, which means they belong in
the onboarding notes and not only in the code.

Applying them to an existing estate is a different exercise from starting with
them. Constraints do not revoke what already exists: keys already issued keep
working, addresses already assigned stay assigned. Adopting them mid-life
requires a separate pass to find and remove what they would have prevented.

The most important consequence is one to guard against: constraints make an
estate look finished. They cover a specific and fairly small set of decisions,
and everything they do not cover is still a convention.

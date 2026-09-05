# 24. What development proves is that it works in development

**Date:** 2026-09-04
**Status:** Accepted

## Context

A release is validated in a development environment, it passes, and it fails in
production. The code is identical. What differed was never in the repository,
so nothing tested it.

Two of these, from the same estate.

**A port that was not open.** A version needed a database on a new port.
Development had it open, production did not, and the application came up and
could not reach its database. Nothing in the change said anything about a port,
because a port is not part of an application. It is part of the network the
application was placed in, and only one of the two networks had been prepared.

**A policy attached to the wrong thing.** An application firewall policy existed
and was associated with a service other than the one it was meant to protect.
It blocked everything. It was also carrying exceptions that had been validated
in development, where they were harmless because the traffic there is not the
traffic here.

Those two failures look unrelated and are the same failure. In each case the
thing that differed between environments was configuration that lives outside
the code: a firewall rule and a policy association. Neither travels with the
release. Neither is exercised by any test. And neither is visible in the diff
that somebody approved.

There is a second, subtler part. A firewall policy that blocks everything is at
least loud. The opposite version of the same mistake, a policy attached to
nothing at all, is silent: the configuration is present, the service answers
normally, and nothing is being protected. Both are the same error, and only one
of them announces itself.

## Decision

Before a release, the things that differ between the environments are listed and
verified rather than assumed. Specifically: the network paths the application
needs, the identities and permissions it runs with, the interfaces it depends
on being enabled, and the policies that are supposed to sit in front of it,
each confirmed to be attached to what it is meant to be attached to.

Exceptions validated in one environment do not transfer to another. An
exception is a statement about traffic, and the traffic is not the same, so it
is re-examined where it will actually apply.

The environments hold the same set of components, so that a difference is a
value rather than an absence. An environment missing a component entirely
cannot be compared with the one that has it.

## Alternatives considered

**More testing in development.** The obvious response and it does not reach
this. The tests passed. They were correct. They ran in a place where the port
was open.

**A staging environment identical to production.** Genuinely effective and
genuinely expensive, and the identity decays within weeks unless somebody is
paid to maintain it. Worth it where an outage is measured in real money; for
most estates the list above catches the same failures for a fraction of the
cost.

**Deploy and roll back quickly.** Useful, and it treats the symptom. A rollback
returns the application to a version that works and does not open the port,
so the next attempt fails the same way.

## Consequences

The list is work before every release, and it is the first thing dropped when a
release is urgent. Urgency is also when it is most needed, which is the whole
difficulty.

It does not catch everything. It catches the differences somebody thought to
write down, which is why each incident of this kind should add a line to it
rather than only be fixed.

And it says nothing about what the application does once it is connected and
reachable. This decision is about the environment around the code, which is
precisely the part that no test in the repository can see.

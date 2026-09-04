# 21. The security posture service is read on a schedule, not at audit time

**Date:** 2026-09-04
**Status:** Accepted

## Context

Cloud platforms provide a service that continuously inspects an estate and
reports what is wrong with it: a bucket that became public, a firewall rule
opened to the world, a virtual machine with an address it should not have, a
key that has not been rotated, a workload running with more permission than it
uses.

It is almost always enabled and almost never read. That is a specific failure
rather than laziness. The findings arrive as a list with no owner, most of them
are about things somebody decided deliberately, and separating those from the
few that matter takes an afternoon nobody has scheduled. So the list grows, and
growing makes it less likely to be read, until it is opened for the first time
during an audit or an incident, when it is a hundred items long and the useful
one is somewhere in the middle.

The value is not in the findings. It is in the *difference* between this week's
findings and last week's, because that difference is a change somebody made and
possibly did not mean to.

## Decision

The posture service is enabled across the whole organisation, not per project,
because the thing worth catching is a project nobody is watching.

Its findings are reviewed on a fixed schedule, and the review is a named
person's job with a recurring slot, not an item on a backlog.

Every finding is dispositioned rather than left open: fixed, or explicitly
accepted with a reason and a date. An accepted finding is muted so it stops
appearing, which is what keeps the list short enough to be read at all. A list
nobody can read is the same as no list.

New findings are what the review is for. The question is never "what is on the
list" but "what is on it that was not on it last time".

## Alternatives considered

**Alert on every new finding.** Sounds better and is worse. The volume is
high enough and the severity mixed enough that alerts train people to dismiss
them, and then a real one is dismissed too.

**Periodic manual audit instead.** What this replaces. It finds what the auditor
thought to look for, at a point chosen by the calendar, and misses everything
between audits.

**Only the highest severity.** Tempting, and it hides the class this is best at
catching: a low-severity finding that is only interesting because it appeared
this week in a project that had none.

## Consequences

The review will be skipped, first occasionally and then structurally. It
produces nothing visible when everything is fine, which is most weeks. Whether
this decision holds is decided by whether the slot survives a busy quarter.

Muting is where it decays in the other direction. Accepting a finding is the
right answer often enough that it becomes the reflex, and an estate where
everything has been accepted reports a clean posture and means nothing. Every
acceptance needs a date and a re-examination, or it is a way of turning the
service off slowly.

And this reports on what the platform can see. Anything outside it: a service
elsewhere, a laptop, an account in an application, is not covered, and reading
a clean report as "we are fine" is a mistake this decision makes easier rather
than harder.

# 15. One access matrix, applied to every system

**Date:** 2026-09-04
**Status:** Accepted

## Context

Access tends to be decided per system. Somebody needs the cloud console, so
they are given a role there. Later they need the ERP, so an account is created
with whatever the person creating it thought reasonable. Then the code
repositories, the dashboards, the ticket tracker.

Each grant is defensible on its own. The problem is that nobody can answer the
only question that matters: what can this person actually reach.

That question has no owner. The cloud lists cloud roles, the ERP lists ERP
roles, and nothing lists a person. When somebody leaves, each system is
remembered separately and some are forgotten. When a role changes, access is
added and rarely removed, so scope grows in one direction for as long as
someone stays.

The compounding version is worse. A modest grant in one system plus a modest
grant in another can produce something neither owner would have approved: read
access to a data store and write access to the pipeline that feeds it is a
different thing than either alone.

## Decision

There is a single matrix, kept outside any one system, listing roles against
what each role may reach in every system. It is the source; each system's
configuration is a projection of it.

A person is assigned a role from that matrix, never a set of grants assembled
per system. Adding a system means adding a column and deciding what every
existing role gets, which is deliberately more work than granting access to
whoever asked.

The matrix is reviewed against what is actually configured. A matrix that is
never compared to reality documents an intention.

## Alternatives considered

**Per-system ownership with periodic review.** How most organisations work. It
functions while each system has an attentive owner and fails at the seams —
which is where the compounding risk lives, since no single owner sees a
combination.

**A single sign-on provider as the matrix.** Better, and the right mechanism for
authentication. Rejected as sufficient because it answers who someone is rather
than what they may do: two people in the same directory group routinely hold
different permissions inside a system, and the provider cannot see that.

## Consequences

The matrix is work with no visible output. It is maintained by someone whose
reward for doing it well is that nothing happens, and it decays first at the
edges — a small tool added quickly, a contractor granted access directly.

It also makes refusals explicit. Once written down, "this role does not reach
that system" is a statement somebody has to defend, rather than a grant that
quietly never happened. That is the point and it is uncomfortable.

The review is the part that will be skipped. A matrix nobody compares against
the running configuration is not a control; it is a document that describes a
system that may no longer exist.

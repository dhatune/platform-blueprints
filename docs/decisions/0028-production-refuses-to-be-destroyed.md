# 28. Production refuses to be destroyed; development does not

**Date:** 2026-09-05
**Status:** Accepted

## Context

Both environments carry the same components, on purpose, so that neither is a
reduced rehearsal of the other. It does not follow that they should be equally
easy to delete.

Today the stack sets the same value in both, and an environment is removed by
not naming it in a list. That is a one-word edit to a variables file, it looks
like configuration rather than demolition, and the plan that follows is a long
list of resources scrolling past somebody who has already decided what they are
doing.

Two near-misses in one afternoon of building this. A teardown script written to
take one environment down called a destroy that is not scoped to anything and
would have taken the other with it. And an edit narrowing that same list was
made while a destroy was about to run, which would have reached past the
environment it was aimed at. Neither was caught by reading the plan.

The thing that makes production different is not that it is more important in
some abstract way. It is that its contents cannot be reconstructed from this
repository. A cluster can. The data somebody put in it cannot.

There is a guard already, and finding it is what makes this a decision rather
than a proposal. The project resource takes a deletion policy, its default
refuses destruction, and the stack does not pass a value, so both environments
inherit the same refusal. It was discovered the way these things are: a
teardown of development destroyed the network, the services and the shared
network attachment, and then stopped on the project itself.

Inheriting it is not the same as choosing it. A guard nobody selected is one
nobody can explain, and the first person who needs to tear down development
will remove it in the place that covers both environments, because that is
where it is written.

## Decision

Deletion protection is asymmetric.

Production is created with the platform's deletion protection enabled, and the
stack refuses to destroy it. Removing it requires changing a value to say so,
in a commit, which is reviewed like any other change and leaves a record of who
decided and when.

Development is created without it. Rebuilding development is the point of
having it, and friction there buys nothing and costs a habit: an operator who
has to disable a guard weekly stops reading it.

The asymmetry is the decision. A guard that is present everywhere is one people
learn to switch off without thinking, and a guard that is nowhere is one that
was never a decision.

## Alternatives considered

**The same setting in both.** Symmetry is the argument for everything else in
this stack, and it is the wrong argument here. Environments should run the same
components; they should not be equally destructible. What symmetry protects is
that what was tested is what runs, and a guard on deletion does not change what
runs.

**Rely on access control instead.** Only let people who should destroy
production be able to. Rejected because the person who destroys it by accident
almost always has the right to destroy it on purpose. The failure is intent,
not authority, and access control does not distinguish them.

**Rely on the plan.** The output says precisely what will be destroyed.
Rejected on evidence: it said so twice today and was not what stopped either
mistake.

**Require a typed confirmation at the prompt.** Better than nothing, and it is
answered by whoever is already committed to the action, in the same minute,
with no witness. A commit is slower on purpose and someone else can see it.

## What this means concretely

The value exists and is not passed. Production should pass the refusing value
explicitly, so that it is a decision with a reason beside it rather than a
default nobody read. Development should pass the permitting one, so that
tearing it down is ordinary and nobody learns to reach for the setting that
covers both.

This is deliberately not implemented here. The decision is worth recording
before the change, because the change is one line and the reasoning is the part
that will be needed in six months when somebody wonders why the two
environments differ.

## Consequences

Destroying production is two acts rather than one: a change that says it is
allowed, and then the destruction. That is friction, deliberately, and it will
be irritating exactly once per legitimate teardown.

The flag can be left enabled after a teardown, which quietly disarms the guard
for next time. Nothing here re-arms it. That is a gap, and the honest options
are a check that refuses a merge leaving production unprotected, or accepting
that the commit is the record and a person reads it.

And it makes the two environments differ in one attribute, which every future
reader will notice and some will try to remove for consistency. The reason is
written here so that removing it is a decision rather than a tidy-up.

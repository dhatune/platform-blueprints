# 12. The images a cluster runs come from a registry we control

**Date:** 2026-09-04
**Status:** Accepted

## Context

A cluster that pulls straight from a public registry has taken a dependency it
does not control and mostly cannot see. Three things go wrong with it, in
rising order of how badly.

Anonymous pulls from public registries are rate limited, and the limit applies
per source address. A cluster that scales out, or a node pool that recycles,
can exhaust it, and then pods stop starting during an incident, which is
exactly when node pools recycle.

A tag can be moved. This repository pins images by digest elsewhere for that
reason. Pinning stops you running something you did not review; it does not
stop the thing you did review from disappearing.

And it can disappear. Upstream deletes it, an account lapses, a project is
renamed. What ran yesterday cannot be rebuilt today, and the failure surfaces
when a node replaces itself rather than when the deletion happened.

## Decision

Workload images are pulled from a registry inside the same organisation. Two
mechanisms, and the difference is worth understanding rather than picking by
which involves less typing.

A **remote repository** is a caching proxy: the cluster pulls from it, and on a
miss it fetches upstream and keeps a copy. Nothing to run and nothing to
schedule. It fixes rate limits and locality on its own.

A **standard repository** holds images put there deliberately, built here, or
copied in at a reviewed digest. Copying is an explicit act with a date and an
author, and the copy survives whatever happens upstream afterwards.

Production pulls from the standard repository, by digest. The cache is for
development and for anything whose disappearance would be tolerable.

Nodes are granted read and nothing more. A cluster able to write to the
registry it pulls from turns one compromised workload into a supply chain
problem for everything else that pulls the same images.

## Alternatives considered

**Pull from upstream and pin by digest.** Simple, and it already solves the
"am I running what I reviewed" half. Rejected as sufficient because a digest is
a name, not a copy: when upstream removes the image the digest still describes
it perfectly and nothing can serve it.

**The cache alone, with no standard repository.** Tempting, because it needs no
pipeline at all. Rejected for production because a cache is a performance
mechanism rather than a retention guarantee; it holds what was recently asked
for, which is not the same as holding what production depends on.

**Building every image from source.** Total control and total cost. Reasonable
for an organisation with the people to maintain it, and a poor trade for one
that would end up maintaining stale forks of things it does not understand.

## Consequences

There is now a step between an upstream release and running it. That is the
point and it is also the friction: someone has to copy the image, and during an
urgent upgrade that step is the one that gets skipped.

Cleanup matters more than it looks. Copies accumulate and are charged for
quietly. Note that deleting untagged images is the wrong policy: a multi
architecture image is an index pointing at per-platform manifests that carry no
tags of their own, and removing them breaks the image on every platform.

The rule is only as good as its coverage. In this repository the workload's own
image was mirrored while its database image was still pulled from a public
registry: a gap found by running it, not by reading it, and recorded in the
n8n section rather than quietly fixed.

# 29. What has to survive a rebuild, and what has to be thrown away

**Date:** 2026-09-05
**Status:** Proposed

## Context

An environment here is built by one command and taken down by another, and the
value of that is not convenience. It is that a cluster nobody is afraid to
replace gets replaced, and one that has been running for two years with
nineteen manual changes in it does not, because nobody knows what would break.

That only holds while rebuilding is genuinely cheap. It stops being cheap the
moment something exists that a rebuild would lose, and the way that happens is
never a decision: somebody creates a database, somebody uploads a file,
somebody generates a key that is now referenced elsewhere.

So the list of what survives has to be short, written down, and enforced by
where things live rather than by discipline. Anything not on it should be
destroyed and rebuilt often enough that everyone believes it can be.

Today the boundary is accidental. The DNS zone survives because Terraform
happens to create it in a project the cluster does not own. The images survive
because the registry is in the shared project. Nothing says either of those is
deliberate, and nothing stops the next addition from landing on the wrong side.

## Decision

Every resource belongs to one of two categories, and the category is a property
of where it is declared rather than of anyone remembering.

**Rebuilt, always.** The cluster, its node pools, the load balancer, the
certificates, every workload and every object inside the cluster. These are
destroyed and recreated without ceremony, and anything that cannot survive that
does not belong in this category. Certificates are reissued rather than
preserved, which the DNS challenge makes free.

**Outlives the environment.** The DNS zone and its delegation, the registry
holding the images, the state, the secrets, and the data. These live in
projects and services that a rebuild does not touch, and they are the only
things that do.

The test for a new resource is one question: if this environment were destroyed
tonight and rebuilt tomorrow from the repository, would anything be lost? If
the answer is yes, it belongs in the second category and has to be moved there
before it holds anything real. If the answer is no, it belongs in the first and
should be destroyed regularly to keep the answer true.

## Alternatives considered

**Back everything up and restore it.** The general answer, and it makes a
rebuild a restore, which is a different and slower operation with its own
failure modes. Rejected as the primary mechanism because a restore that runs
once a year is a belief, and because most of what is in a cluster should not be
restored, it should be recreated from the repository. Backups remain necessary
for the data in the second category and are not a substitute for this
boundary.

**Make everything immutable and never rebuild.** Replace nothing, patch in
place. Rejected because it is how a cluster accumulates the nineteen manual
changes, and because the platform upgrades underneath it whether or not anyone
is ready.

**Decide case by case.** What happens now. Rejected because it is not a
decision, it is the absence of one, and the boundary it produces is wherever
each resource happened to be declared.

## Consequences

Some things have to move before this is true. The secrets are generated into
the cluster by the installer, which puts them in the first category while
behaving as though they were in the second: a rebuild silently issues new ones,
and the automation service's encryption key in particular takes every stored
credential with it. The databases are on volumes in the cluster, which is the
same problem with more of it.

Until those move, a rebuild of a production environment is not the cheap
operation this decision assumes, and saying otherwise would be the dangerous
part.

The second category needs its own protection, and that is ADR 28: the things
that outlive an environment are exactly the things whose deletion has to be
deliberate.

And the first category needs to be exercised. A rebuild that is possible in
principle and has not been done in six months is a claim, not a capability. The
only way to keep it true is to destroy and rebuild development often enough
that it is boring.

## Status

Proposed rather than accepted, because two of the things it says belong in the
second category are currently in the first, and a decision the code contradicts
is a wish. It becomes accepted when the secrets and the data have moved.

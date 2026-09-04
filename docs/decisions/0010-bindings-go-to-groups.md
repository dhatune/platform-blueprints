# 10. Bindings go to groups, never to people

**Date:** 2026-09-03
**Status:** Accepted

## Context

Granting a role to a person is the fastest way to unblock them, and it works.
The cost arrives later and somewhere else.

When that person changes teams or leaves, their access has to end. If the
binding names them directly, ending it means finding every place their address
appears, across folders, projects, buckets, secrets, databases, and removing
each one. Nobody does this reliably, because nobody knows the full list. What
actually happens is that the obvious grants are removed and the rest stay,
indefinitely, attached to an account that may still exist.

The failure is quiet. Nothing breaks when stale access remains, so there is no
signal, and the estate accumulates permissions belonging to people who are no
longer there. An audit eventually finds them, long after they mattered.

## Decision

Every binding names a group. Individuals are added to groups in the directory
and nowhere else.

The infrastructure defines which groups hold which roles. Who is in a group is
a separate question with a separate answer, managed where joining and leaving
the organisation is already handled.

Primitive roles are refused at plan time. They are convenient precisely because
they are broad, and an estate that admits them at folder level has no least
privilege regardless of what the rest of its configuration says.

## Alternatives considered

**Direct bindings with a periodic audit.** This is what most organisations
actually do. It works to the extent the audit runs and someone acts on it, and
it fails in the gap between a person leaving and the next audit, which is
exactly the window that matters.

**Direct bindings with an expiry condition**, so a grant lapses on its own.
Genuinely useful, and better than nothing where a group cannot be used. It was
rejected as the primary mechanism because it makes access disappear on a
schedule unrelated to whether the person still needs it, which trains everyone
to grant longer expiries.

## Consequences

Granting access now requires a group to exist, which is slower than typing an
address, and the slowness is felt every time while the benefit is invisible.
Expect pressure to make an exception "just this once", usually during an
incident.

The model is only as good as the directory. If group membership is unmanaged,
this moves the problem rather than solving it: a group that nobody prunes is a
direct binding with extra steps.

Automation identities are the exception, since a service account is not a
person and does not belong to a group. They are named directly, which makes
them conspicuous in a diff, which is the point.

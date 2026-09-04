# 8. Stateless is not the same as interruptible

**Date:** 2026-09-03
**Status:** Accepted

## Context

A workflow automation service keeps all of its state in a database. There is no
persistent volume, nothing important in the container, and a restart loses
nothing. By every checklist used to decide where a workload belongs, it is a
candidate for the cheapest capacity a platform offers: preemptible instances,
aggressive bin-packing, eviction whenever the scheduler wants the room.

The checklist is asking the wrong question. "Can this be restarted safely?" and
"can this be interrupted safely?" are different properties, and only the first
one follows from having no local state.

What happens on eviction is not a rollback. A workflow that was running is
recorded as crashed, and whatever it had already done stays done. A workflow
that sends invoices sends some of them. A workflow that posts to five places
posts to two. The database is perfectly consistent about the fact that
something ran halfway, which is not the same as the work being safe to lose.

There is a second cost that is easy to miss. This kind of service is usually
one of the smallest workloads on a cluster, so its resource request is often
the last thing keeping an additional node alive. That makes it a tempting
target for consolidation, and the temptation is strongest for exactly the
workload where interruption is least visible, nobody watches a scheduled job
the way they watch a web service.

## Two reasons, and the second one is the common one

The argument above is about work in flight: an eviction leaves an execution
half done, and half done is not the same as rolled back.

There is a second reason, and in practice it is the one that decides it.

The thing was being used all the time, in the operation, to serve requests that
had to be executed when they arrived. If it was not available, there were
problems, not later, not in a report, immediately.

That is a different property from whether work can be resumed. A batch job that
runs at three in the morning can be evicted and retried at four and nobody
notices. Something answering requests as they come in has to be *there*, and
"there" is exactly what interruptible capacity does not promise.

It is worth separating them because they lead to different fixes. Work that
cannot be interrupted safely can be made safe, with queues and idempotency and
workers that can be lost. Something that has to be present when a request
arrives cannot be fixed that way: it either has capacity that is not taken away
or it does not.

## Decision

The workload runs on non-preemptible capacity, and the reason is written in the
manifest next to the node placement rather than in a document nobody opens
while editing YAML.

The update strategy replaces the pod rather than overlapping two, for the same
reason: not because two pods would corrupt anything, but because an execution
interrupted mid-run does not resume.

## Alternatives considered

**Preemptible capacity with retries on failed executions.** This is the correct
answer for workflows that are idempotent, and it is cheaper. It was rejected as
a default because idempotency is a property of each individual workflow, not of
the platform, and the platform cannot verify it. Making the safe choice depend
on every future author getting it right is not a control.

**Preemptible capacity with a queue-based execution mode**, where workers can be
lost without losing the execution. This genuinely solves the problem and is the
right answer at scale. It was rejected here as too much machinery for a single
instance, and it is the first thing to revisit if the cost of dedicated capacity
becomes real.

## Consequences

It costs more, continuously, and the saving that was given up is easy to
calculate while the incident that was avoided is not. This decision will look
wrong in every cost review, and the argument for it has to be made again each
time.

The reasoning is recorded next to the configuration it explains, because the
person who deletes the node placement will be reading the manifest, not the
architecture documentation.

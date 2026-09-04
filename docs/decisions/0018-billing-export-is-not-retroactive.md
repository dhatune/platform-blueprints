# 18. Billing detail is exported on the first day, because it is not retroactive

**Date:** 2026-09-04
**Status:** Accepted

## Context

The console shows what was spent. It does not answer the questions that
actually come up: which of these projects grew, what changed the week the
invoice doubled, which service inside a project is responsible, what this
customer costs to serve.

Those need the detailed records, and the detailed records exist only if they
are being exported to a queryable store. The export is a switch, and the
important property of that switch is that **it is not retroactive**. Turning it
on today produces data from today. The month somebody is asking about is gone,
permanently, and no support request recovers it.

That makes this unlike almost every other decision in a platform. Most can be
deferred at the cost of doing them later. This one is deferred at the cost of
never being able to answer questions about the period it was deferred through , 
and the questions arrive precisely when spending has become alarming, which is
after the interesting months have already passed.

The cost of the export itself is small and proportional: storage of rows, plus
whatever is queried.

## Decision

Detailed billing export is enabled when the billing account is created, before
any workload exists, and treated as part of the account rather than as
analytics that can wait for a reason.

The exported data is the source for cost questions. Labels are applied to
resources so that those questions can be answered by product, environment and
customer rather than only by project, since an unlabelled resource is invisible
to every breakdown that matters.

## Alternatives considered

**Budgets and alerts alone.** Necessary, and they answer a different question:
they say spending crossed a line, not what crossed it. Keep them; they are not
a substitute.

**Enable the export when there is a question.** The default, by inaction. It
guarantees the first serious cost investigation begins by discovering that the
relevant period was never recorded.

**Read the invoices.** Fine for a total. Useless for attributing a change,
which is what anyone actually needs.

## Consequences

Data accumulates and is charged for, modestly, forever. Expiring the oldest
partitions is worth setting up early, and is a separate decision from whether
to export at all.

The export answers questions about cost, which is not the same as controlling
it. It is entirely possible to build careful dashboards and change nothing;
this decision produces the evidence, and acting on it is not automatic.

Labelling is where this decays. The export is only as useful as the labels on
the resources, and labels are applied by whoever creates a resource, so the
breakdown quietly degrades as an estate grows, and the fix is enforcement at
creation rather than a periodic tidy-up.

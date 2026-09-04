# 14. What logs cost is decided at ingestion, not at deletion

**Date:** 2026-09-04
**Status:** Accepted

## Context

Logging is billed on what is accepted, not on what is kept. Shortening
retention after the fact reduces what is stored and does nothing about the
larger number, which was charged when the line arrived.

This inverts the usual instinct. The question that feels responsible — "how
long should we keep these?" — is the second question. The first is which lines
should be accepted at all.

Three things make this expensive quietly.

Audit logs are not one thing. The record of who changed a configuration is
retained for a long period at no charge and cannot be turned off, which is
correct: it is the account of what happened to the estate. The record of who
read which row is a separate category, is off by default, and is enormous.
Enabling it across an organisation because it sounds prudent can cost more than
the workloads it observes.

Defaults are generous. A managed platform will happily accept every log its
components emit, and the configuration that controls this is often several
fields rather than one — leaving any of them unset accepts everything.

And the bill arrives detached from the cause. The line is written by a
component nobody chose, in a project nobody is watching, and the invoice says
"logging".

## Decision

Ingestion is configured explicitly, per project and per component, rather than
left to defaults. Anything not needed is excluded before it is accepted.

Retention is then set per bucket according to what the logs are for: short for
operational noise that is only read during an incident, long for the records
that exist to answer questions about the past. Audit records that are retained
at no charge are left alone; anything read-level is enabled deliberately, for
named systems, with the cost understood.

Logs worth keeping for years are exported to object storage rather than kept in
the logging service, where the same bytes cost a fraction.

## Alternatives considered

**Keep everything and shorten retention.** The common approach and the one that
sounds thrifty. It reduces the smaller of the two charges and leaves the larger
one untouched.

**Sample.** Effective for high-volume traces where a fraction answers the same
question. Rejected as a general policy because it is wrong for exactly the
records this is most about: an audit trail with gaps is not an audit trail.

## Consequences

Excluding a log is a decision made before anyone needs it, which means it will
occasionally be the wrong one, discovered during an incident when the line that
would have explained things was never accepted. That risk is real and is the
argument for excluding narrowly and by name rather than by broad pattern.

This has to be revisited when a component is added, because a new workload
brings new defaults with it. It is not a decision that stays made.

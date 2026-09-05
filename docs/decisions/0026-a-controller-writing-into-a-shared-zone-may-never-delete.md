# 26. A controller writing into a shared zone may never delete

**Date:** 2026-09-05
**Status:** Accepted

## Context

The controller that publishes hostnames writes into a DNS zone. Where that zone
belongs only to the automation, the question below does not arise. Where it is
the zone that also carries the organization's mail records and the address of
its website, it does.

The controller has a mode in which it reconciles the zone against what it
observes in the cluster, and removes records it does not account for. That is
correct behavior for a zone it owns, and it is the setting a reasonable person
reaches for after decommissioning a service and finding its name still
resolving.

Against a shared zone, the records it does not account for include the mail
exchange records. The distance between an ordinary cleanup and an outage that
nobody attributes to DNS for several hours is one flag.

## Decision

A controller that writes into a zone it does not exclusively own runs in a mode
that can create and update records and cannot delete any, and is additionally
confined to one subtree of the zone by a domain filter.

It also records ownership in a text record beside each entry it manages, so its
own records are distinguishable from ones a person created, and so two clusters
publishing into the same zone do not overwrite each other.

The filter and the ownership record are hygiene. The inability to delete is the
control, and it is the one that survives somebody editing the configuration
without reading it.

## Alternatives considered

**Let it reconcile fully.** The correct setting, and the one that keeps the zone
honest, for a zone dedicated to this purpose. Rejected for a shared zone
because the blast radius of a misconfiguration is the organization's mail
rather than one hostname, and because the setting is a single argument that
reads as harmless.

**Give the automation its own zone and delegate a subdomain to it.** Better
than this decision wherever the delegation can be arranged, since it removes
the shared blast radius rather than constraining it, and full reconciliation
becomes safe again. Not rejected on merit. It requires control of the parent
zone's delegation, which is often held by somebody else, and this decision has
to hold in the meantime.

**Write the records by hand.** No controller and no permission. Rejected
because the records then drift from what the cluster actually serves, and the
drift is discovered by a name that resolves to a load balancer that no longer
exists.

## Consequences

Stale records accumulate. Every hostname the controller ever published stays in
the zone after the service is gone, and comes out by hand or not at all. This
is the direct cost of the decision and it is paid continuously.

Worse, nobody notices them accumulating, because nothing reports on records
that should not be there. The zone gets steadily less trustworthy as a
description of what exists, which is the property it was supposed to have.

A periodic reconciliation, run by a person against a list of what is actually
deployed, is the compensating control. Naming it here is not the same as having
it, and this repository does not have it.

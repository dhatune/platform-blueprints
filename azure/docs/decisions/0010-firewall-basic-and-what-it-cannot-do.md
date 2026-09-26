# 10. Firewall Basic, and what it cannot do

## Decision

The egress firewall runs on the Basic tier. Every tier bills per deployment
hour and per gigabyte processed; Basic has the lowest hourly rate, $0.395/h
in `eastus2`, and a higher per-gigabyte rate, $0.065/GB (retail catalogue,
2026-09-25). For a laboratory that is up a few hours at a time and moves
little data, the hourly rate is what matters. Basic is the cheapest tier that
provides stateful filtering, and the lab does not need what the higher tiers
add.

## Alternative it beat

Standard or Premium, which add features this lab does not exercise: Standard
adds DNS proxy and network-level FQDN filtering (this lab has no network
rules and relies on an FQDN tag in application rules instead); Premium adds TLS inspection and signature-based intrusion detection
and prevention (IDPS). See [Azure Firewall features by
SKU](https://learn.microsoft.com/en-us/azure/firewall/features-by-sku).

## What it costs

Basic has no DNS proxy, and no DNS proxy means no FQDN filtering in *network*
rules. A network rule written with a hostname as its destination is accepted
by the provider without complaint and matches nothing at runtime, because
Basic never resolves it to compare against traffic, the same silent-inertness
failure as a mistyped policy alias in docs/decisions/0008, produced by a
different mechanism. `modules/firewall`'s destination guard exists precisely
because of this: it refuses a hostname-shaped destination in a network rule at
plan time, before it can deploy clean and filter nothing.

## What the lab relies on instead

FQDN *tags* (a Microsoft-maintained, coarse-grained allowlist matched in
*application* rules) do work on Basic, and `AzureKubernetesService` is
exactly the mechanism the cluster's egress relies on. Nothing in this
landing zone pulls images from `docker.io` or any other public registry at
run time: every image runs from our own registry, where it is imported by a
control-plane call, or from `mcr.microsoft.com`, which the FQDN tag covers.
There is no FQDN network rule this design would have wanted to write and
could not.

## What to change if this ever needs more

If the blueprint grows a dependency that needs FQDN filtering at the network
rule level (Basic has no DNS proxy for network-rule resolution), or signature-based
intrusion detection, the fix is to move to Standard or Premium respectively.
The tier is set in two places in `modules/firewall`, the firewall policy and
the firewall itself, and both change together; nothing else in the module's
shape depends on the tier. See [Azure Firewall features by
SKU](https://learn.microsoft.com/en-us/azure/firewall/features-by-sku).

## Known limits of the destination guard

The guard in `modules/firewall/variables.tf` stops accidents, not someone with
commit rights who means to defeat it:

- **`Storage.io` is accepted.** A service tag followed by a lowercase token is
  how `AzureCloud.eastus2` is written, and a top-level domain has the same
  shape. Telling them apart needs a list of Azure regions, which goes stale.
- **IPv6 literals are refused.** The module is IPv4-only throughout, and
  nothing in this landing zone uses IPv6.

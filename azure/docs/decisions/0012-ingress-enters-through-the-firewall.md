# 12. Ingress enters through the firewall, and the firewall erases the client

## Decision

Traffic from the internet reaches applications in the cluster through a
destination-address translation rule on the hub firewall, forwarding to an
internal load balancer at a fixed private address, in front of an ingress
controller that does the layer 7 work.

```
internet -> firewall public address (L4)
         -> internal load balancer, 10.61.1.240 (L4)
         -> ingress controller (L7: TLS, host, path)
         -> pod
```

No component in the spoke holds a public address. The firewall's own data
address is the single way in and the single way out.

## Context

Three constraints decided this between them.

**The trial subscription's public-address quota is three, and the firewall
already spends two**, one for its data plane and one for the management plane
the Basic tier requires (see 0010). The limit belongs to the subscription
type, not to Azure, but it is the one this laboratory runs under. A public load balancer per application is the shape
Kubernetes reaches for by default, and it does not fit in what is left.

**The cluster's API server is private.** Nothing about this can be installed
from a laptop; every `kubectl` runs inside the cluster through the managed
command channel, and that pod's egress leaves through the same firewall as
everything else. Nothing may be fetched at install time.

**The firewall allows the spoke out to one set of destinations only**: the
`AzureKubernetesService` FQDN tag (0010). The registry the ingress project
publishes to is not in it, deliberately. A manifest
pointing at it yields pods that never start.

## What follows from it

### The two halves cannot see each other, so they are told the same number

Terraform declares the translation rule and cannot read Kubernetes.
Kubernetes declares the load balancer and cannot read Terraform. The only
agreement two such systems can keep across a redeploy of either is a value
both are given: `var.ingress_internal_address` in `live/lab/20-workload` and
`INGRESS_INTERNAL_ADDRESS` in `scripts/lib/ingress.env`.
`scripts/ingress/install-nginx.sh` compares them and refuses to run when they
differ, because the failure mode otherwise is a load balancer at one address
and a rule pointing at another: a connection that times out with nothing in
any log.

### The annotations are set before the service exists

A Service of type LoadBalancer without them takes a public address
immediately. Patching it afterwards means one was allocated, held and
released against a quota of three for no reason. The renderer inserts them
into the manifest; nothing is patched after the fact.

### The images are imported by digest

`az acr import` is a control-plane call (the registry performs the pull
server-side) so it works from a machine with neither data-plane access to
the registry nor a container runtime. Importing by digest rather than tag
means the copy we run is provably the artefact the vendored manifest was
reviewed against, and an upstream retag cannot change what runs.

### The upstream manifest is vendored

Not fetched. The apply runs inside the cluster, behind the same firewall,
and a change to what the cluster contains should appear in review as a diff.

### A rule the path does not work without, and a route it does not need

The load balancer's health probe arrives from the platform host address,
which is inside the `VirtualNetwork` service tag. The deny-by-default at
priority 4000 catches it, and the Azure default that admits it sits at 65001,
below the deny, never evaluated. Without an explicit rule the load balancer
comes up, takes its address, reports no healthy backend and drops
everything. The probe never crosses the firewall, so the firewall's logs show
nothing; the VNet flow logs this landing zone enables are where it appears.
The same blind spot applies to nodes reaching the control plane, whose
private endpoint AKS places inside the node subnet: the
`cluster_to_cluster_all` rule in `live/lab/10-platform` covers both.

No return route is needed. Because the firewall translates the source of DNAT
traffic to its own private address (below), the reply goes back to that
address over the peering and never consults the spoke's route table. Check 9
passes with no route for the firewall's public address.

The spoke's default route is its own `azurerm_route` resource rather than an
inline block of the route table, so another layer can add routes without the
two deleting each other's on every apply.

## The consequence worth planning around

**The firewall translates the source address as well as the destination.**
This is documented behaviour: Azure Firewall always applies source
translation to traffic that matches a DNAT rule, so that the reply returns
through the firewall and the session stays stateful (see
[Azure Firewall NAT behaviors](https://techcommunity.microsoft.com/t5/azure-network-security-blog/azure-firewall-nat-behaviors/ba-p/3825834),
linked from the [Azure Firewall FAQ](https://learn.microsoft.com/en-us/azure/firewall/firewall-faq)).
Check 9 reproduces it on every run: the ingress controller's access log
records the caller as an address in the firewall's own subnet, never the
client's.

So nothing behind this path knows who called. No rate limiting per client, no
geographic rules, no access log worth reading for abuse.

There is a trap in the obvious fix. `externalTrafficPolicy: Local`, which
preserves the source address through the load balancer and ships enabled in
the upstream manifest, is exactly what one would reach for and buys nothing
here: it preserves the address it receives, and the address it receives is
already the firewall's. The information was lost one hop earlier.

Anything needing the caller's address has to read it from a header set
further out, which means something further out has to exist, an application
gateway or a global edge, each its own product with its own price floor and
its own lifecycle. If a requirement mentions per-country rules, per-client
rate limiting, or visitor traceability, **translation on the firewall does not
suffice as the entry path** and that piece must be budgeted from the start.

## What was rejected

**A public load balancer per application.** The shape Kubernetes defaults to.
Spends a public address per service against a quota of three, and takes
inbound traffic out of the firewall's view entirely.

**Application Gateway for Containers.** Azure's managed Gateway API
implementation. It needs its own
delegated subnet, which `modules/network-spoke` does not support, plus a
controller in the cluster holding write permissions on Azure network
infrastructure. Worth doing; not worth doing first.

**A maintained ingress controller.** Upstream ingress-nginx is retired: the
Kubernetes project announced it in November 2025 and best-effort maintenance
ended in March 2026 (see the
[Kubernetes announcement](https://www.kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/)).
It is used here only as a minimal layer 7 hop that proves the path and what
the firewall does to it. A production composition would use Application
Gateway for Containers or another maintained Gateway API implementation.

**A global edge in front.** Its components bill monthly and do not prorate,
which breaks the discipline of destroying the ephemeral layer between
sessions (0003).

## Consequences

- One public address serves both directions: all egress leaves by it and all
  ingress arrives at it. That single identity is the thing a third party can
  put on an allow list, and it is the strongest practical argument for this
  topology over a distributed one.
- Layer 7 lives in the cluster, so the manifests are portable: nothing about
  the ingress declaration is Azure-specific except the two service
  annotations.
- There is no managed WAF and no TLS on this path. None is being validated.
- The entry path is only as available as the firewall, which is one hop and
  one failure domain. Acceptable for a laboratory; a production composition
  would state it explicitly rather than inherit it.

# The edge

How a service inside a cluster becomes a name on the internet with a valid
certificate in front of it, and what each of the four pieces costs.

Nothing here is specific to the workload behind it. The example targets the ERP
in `platform/erpnext` because that is what it was verified against.

## What is here

```
base/                the shared edge, applied once per environment
  external-dns.yaml    publishes hostnames into a zone it does not own
  cert-issuer.yaml     obtains certificates by writing DNS
  gateway.yaml         the one entry point, its wildcard certificate, and
                       the redirect from 80
overlays/dev/        the values that differ, per environment
overlays/prod/
workload-template/   what a workload copies to become reachable: its route,
                     its health check and its firewall attachment
```

One Gateway for the whole environment rather than one per service. Each
Gateway builds its own load balancer and is billed for it, so three services
with three Gateways pay three times to do one job. The listener carries a
wildcard, so adding a service costs a route and nothing here.

A wildcard certificate can only be obtained by writing DNS, because the other
challenge answers on a name and a wildcard is not one. ADR 25 chose the DNS
challenge for a different reason; this comes free with it.

## Where your own values go

One file per environment, not in version control, in the same arrangement the
Terraform stack uses:

```
cp overlays/dev/values.env.example overlays/dev/values.env
```

Fill it from the stack that built the cluster:

```
terraform -chdir=../../lab output -json environments
```

| Key | What it is |
| --- | --- |
| `wildcard` | the names this environment serves, as one wildcard: `*.dev.lab.example.test` |
| `domainFilter` | the subtree the publisher may write into, and nothing wider |
| `dnsProject` | the project holding the zone, usually not this environment's |
| `txtOwnerId` | unique per cluster; two clusters sharing it fight over every record |
| `dnsServiceAccount` | the identity both controllers assume, which holds no key |
| `acmeEmail` | an address somebody reads, and the only expiry warning there is |

Then `kubectl apply -k overlays/dev`.

## The blank that gets deployed

Kustomize substitutes by selecting the objects to change. A selector that
matches nothing is **not an error**: it prints no warning, exits successfully,
and the placeholder survives into the output. What reaches the cluster is a
Gateway whose hostname is the literal string `REPLACE_ME_WILDCARD`, and every
tool in the chain reported success.

Rendering the overlay and reading the result is the only place that failure is
visible, so the checks do exactly that and refuse output that still contains a
blank. Two other things they check, for the same reason: that the example file
still has every key the overlay asks for, and that no two environments share a
`txtOwnerId`. That last one no templating tool can catch, and it is only ever
wrong because somebody copied one environment to make the next, which is how
the next one gets made.

## The ordering problem, which is the whole reason for the DNS challenge

The obvious way to prove control of a name is to answer a request on it. That
requires the name to resolve here and the entry point to be serving already,
and on a first deployment neither is true: the Gateway will not become ready
without a certificate, and the certificate cannot be issued without a Gateway
answering. It deadlocks, and it deadlocks silently, with both objects reporting
that they are waiting.

Writing a DNS record proves the same thing with no such ordering. It also works
for a name that is never publicly reachable, which the HTTP challenge cannot do
at all.

The cost is a permission. The issuer has to write into the zone, which is the
same permission the record publisher already holds, so they share one identity
rather than two. That identity is assumed through the cluster's workload
identity pool and holds no key. ADR 5.

## The zone is not owned by the cluster

The zone here also serves the domain's mail and its website, and it lives in a
different project from the cluster. Two consequences.

The permission is cross-project, granted in the project that owns the zone
rather than in the one running the workload. It is easy to grant in the wrong
place, and the failure is a controller that starts cleanly and logs a
permission error on every reconcile.

And the blast radius is the whole domain. Two limits are applied for that
reason and only one of them matters. The domain filter confines the controller
to a subtree. `upsert-only` is the one that counts, because this controller has
a mode that deletes any record it does not recognize, and that mode is one flag
away from someone making a decommissioned service stop resolving. Set to sync,
against a zone holding the business's MX records, it is a single flag between a
routine cleanup and losing mail.

What upsert-only costs is real: it cannot delete its own records either, so
stale names accumulate and come out by hand. For a zone that belongs to the
automation, sync is the right answer. For one that belongs to the business it
is not.

## What was verified

Deployed to a cluster on a shared network, exercised end to end, and torn down
with the rest of the lab.

```
certificate        issued by the public authority via the DNS challenge,
                   valid, served by the Gateway
HTTPS from the     200 on the application's own login page, from outside
internet           the network
redirect           301 from port 80 to 443
application        403 on a request carrying an injection, 200 on an
firewall           ordinary one, at the same time
record publishing  the hostname and its ownership TXT written into the zone
                   by the controller, with no key anywhere
```

Two things surfaced only by running it.

**The Gateway answers nothing while it is being built.** The object exists, the
status is empty rather than failed, and it stays that way for minutes. Every
instinct says the configuration is wrong. It is not, and the only way to know
that is to have seen it before.

**The health check needs to be told which host to claim.** It probes the pod
with no Host header, the application routes by hostname, does not recognize the
request and answers 404. The backend is marked unhealthy and every request gets
503 while the application is perfectly healthy. The application logs a 404 from
an internal address and the user sees a 503, and nothing in either message says
"health check".

## What this does not cover

One cluster, one hostname, one zone. Two clusters publishing into the same zone
is what the ownership TXT record exists for and it was not exercised.

Certificate renewal was not observed. It happens around sixty days in, long
after a lab is gone, and it is the moment a DNS permission that was quietly
revoked in between becomes an outage.

The ACME account key is created and never backed up, which is the default and
is worth naming. Losing it does not invalidate what was issued; it loses the
rate limit history and the ability to revoke as that account.

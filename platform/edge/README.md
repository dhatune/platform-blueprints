# The edge

How a service inside a cluster becomes a name on the internet with a valid
certificate in front of it, and what each of the four pieces costs.

Nothing here is specific to the workload behind it. The example targets the ERP
in `platform/erpnext` because that is what it was verified against.

## The four pieces

```
external-dns.yaml    publishes the hostname into a zone it does not own
cert-issuer.yaml     obtains the certificate, by writing DNS rather than
                     answering on the name
gateway.yaml         the load balancer, the certificate it serves, and the
                     routes: one proxying, one redirecting 80 to 443
health-check.yaml    tells the probe which host to claim
backend-policy.yaml  puts the application firewall in front of the backend
```

## Filling these in

The manifests carry placeholders rather than values. Each one has a source,
and all but two come from the stack that built the cluster:

```
terraform -chdir=../../lab output -json environments
```

| Placeholder | Where the value comes from |
| --- | --- |
| `REPLACE_ME_HOST` | the hostname you are serving: a name of your choosing under the environment's `dns_domain`, for example `erp.dev.lab.example.test` |
| `REPLACE_ME_DOMAIN` | that environment's `dns_domain`, and nothing wider. It is the only thing stopping this controller from touching the rest of the zone |
| `REPLACE_ME_DNS_PROJECT` | the project holding the zone, `dns_project` in the stack's variables |
| `REPLACE_ME_CLUSTER_ID` | the environment's `cluster`. It has to be unique per cluster, because it is how two clusters sharing a zone tell their records apart |
| `REPLACE_ME_SECURITY_POLICY` | the environment's `security_policy` |
| `REPLACE_ME_EMAIL` | an address you read. The certificate authority writes to it before a certificate expires, and it is the only warning you get |

The service account annotation in `external-dns.yaml` is already the identity
the stack creates, so it needs the project substituted and nothing else.

Substituting by hand is fine for one environment and is the wrong answer for
two. Whatever templating the rest of an estate already uses belongs here; this
repository does not pick one, because that choice belongs to the estate rather
than to the pattern.

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

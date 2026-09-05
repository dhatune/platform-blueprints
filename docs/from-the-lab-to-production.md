# What this lab is not, and what it would take

The `lab/` stack builds an environment called production and it is not one. It
is the same set of components as development, deliberately, so that neither is
a reduced rehearsal of the other. That is a different claim from being ready to
carry a business.

This is the list of what would have to change, written from what building it
actually surfaced rather than from a checklist. Each item says what it costs to
leave alone, because the point of naming them is that some of them are fine to
leave alone for a while and it should be a decision.

## Blocking. Do not run a business on this without these.

**Nothing is backed up.** Not the ERP's database, not the automation service's
Postgres, not the password manager's volume. ADR 7 in this repository argues
that a backup nobody has restored is a belief, and here there is not even the
belief. The password manager holds the credentials to everything else, so its
loss is not an outage.

**Secrets are generated and thrown into the cluster.** The bootstrap creates
them with `openssl` and applies them directly. ADR 22 says secrets are
referenced rather than passed, and a real environment takes them from a secret
manager. Two specifics matter more than the principle: the automation service's
encryption key is regenerated on every fresh cluster, and losing it costs every
stored credential even with a perfect database backup; and the ERP's
administrative password is printed once to a terminal and cannot be retrieved
afterwards, only replaced.

**The ERP's shared storage is a single pod.** It runs an NFS server inside the
cluster on a single-attach disk. When that pod goes, every web process, worker
and scheduler loses its filesystem at the same instant and the ERP stops rather
than degrading. Moving it means detaching and reattaching a disk, which is
minutes of downtime during an ordinary node upgrade. The section's own README
says this is the right answer for an internal system and the wrong one for
anything customer-facing, and the invoice for a managed file service is the
cheaper problem.

**The password manager is reachable by anyone who can resolve its name.** ADR
16 argues for an identity check in front of a system this sensitive, so that an
unauthenticated request never arrives and a flaw in the application's own login
cannot be reached by a stranger. The route deployed here does not do that.

## Structural. The shape is wrong for production, not just the settings.

**The cluster has one control plane.** It is zonal because a regional one is
three times the charge for something that exists for an afternoon. A zone going
away takes the whole environment with it.

**The default node pool is interruptible.** ADR 8 is about the difference
between restarting safely and being evicted safely, and the stateful pool
exists for exactly that reason. In production the split has to be deliberate
per workload rather than "everything cheap except the one that complained".

**There is no autoscaling, no maintenance window and no pinned release
channel.** The cluster upgrades when the platform decides, and the node count
is whatever was typed.

**Images come through a caching proxy, not a copy.** The proxy serves what
upstream serves, so a tag that is rewritten or deleted changes what a
deployment gets. ADR 12 asks for a repository holding an image that was
reviewed, and closing that gap means a build running inside the platform
rather than on somebody's laptop. Copying through a laptop was tried during
this build and one image took over an hour, which is the reason it is not the
answer.

**Nothing verifies where an image came from.** No signature, no provenance.

## Operational. It will run, and nobody will know what it is doing.

**Only system metrics are collected**, because the platform's default enables
every billable collector and the charge arrives under a name that does not
mention the cluster. That was the right call for a lab and it means no
application metrics exist.

**There are no alerts and no log destination.** ADR 14 says retention is
decided at ingestion and nothing here decides it.

**A failed job is sitting in the ERP's namespace right now.** The chart's
migration job races the job that configures the bench and exits reporting a
missing file. The end state is correct. In production that is a red job nobody
investigates, next to the restart noise the section already documents, and the
cost is that a real failure looks the same.

**Certificate renewal has never been observed.** It happens around sixty days
in, long after any lab is gone. A DNS permission quietly revoked in between is
invisible until the certificate expires on a working service.

**The ACME account key is not backed up.** Losing it does not invalidate what
was issued; it loses the rate limit history and the ability to revoke.

## Smaller, and each one bit during this build

**The health check port list is maintained by hand.** The probe ranges are
allowed to reach a fixed set of ports, and a workload serving on a port not in
that list is marked unhealthy while running perfectly. Nothing in any log
connects the 503 to the network module. Adding a workload means remembering to
add its port.

**The entry point accepts routes from every namespace.** That is deliberate, so
that teams do not share one writable namespace, and it means anyone who can
create a route can publish a name under the wildcard.

**The storage class named for encryption uses the platform's own.** A real
environment defines it with a key the organization controls, so that destroying
the key destroys the data.

**Mail does not work.** The password manager's SMTP credentials are
placeholders that exist only because the deployment refuses to start without
them. Invitations and password resets fail.

## Process, which is the one people skip

**Applies happen from a laptop.** `docs/git-flow.md` says infrastructure is
applied only from `main` after review, and nothing enforces that. There is no
pipeline running a plan on a pull request, so the review is of code that nobody
has seen planned.

**The environment name is a variable and the identifiers carry a random
suffix**, which exists so a lab can be rebuilt inside the thirty days a
destroyed project's identifier is held. A real environment has a name that
never changes, and that changes how the stack is written.

**Nobody has run this twice from nothing.** Until the same commit produces the
same working environment on a machine that is not the author's, "it works" is a
statement about one afternoon.

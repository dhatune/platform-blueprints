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

---

# The changes, concretely

The sections above say what is missing. This one says what to change and where,
because a gap described in prose is a gap nobody closes.

Each entry has the same shape: what it is now, why it is that way, and the
change. The "why" matters as much as the change. Most of these were not
oversights, they were the cheapest thing that let the verification run, and
knowing which is which tells you what is safe to keep.

## The cluster: `landing-zone/modules/cluster/main.tf`

**One control plane instead of three.**
Now: `location = var.zone`, and the lab passes `us-east1-b`.
Why: a zonal cluster was enough to prove the components work, and the
verification existed for an afternoon.
Change: pass a region rather than a zone. The control plane is then replicated
and survives one zone going away, and node pools place nodes across the
region's zones, which multiplies the node count by the number of zones.

**Interruptible nodes carrying everything except what complained.**
Now: `spot = true` on the default pool.
Why: ADR 8 is about the difference between restarting safely and being evicted
safely, and the stateful pool exists because one workload declared it needed
that. Everything else stayed on interruptible capacity because nothing forced
the question.
Change: the decision belongs per workload rather than per default. Interruptible
capacity is right for work whose restart costs nothing and wrong for anything
recorded as started.

**Nothing decides when the cluster upgrades.**
Now: neither `release_channel` nor `maintenance_policy` is declared, so the
platform upgrades on its own schedule.
Why: never came up. A cluster that lives for hours is not upgraded.
Change: declare both. The channel decides how new the version is and how soon
it moves; the maintenance policy decides what hours are acceptable. Without
them, a node pool recreates itself during business hours and nobody scheduled
it.

**The node count is whatever was typed.**
Now: `node_count` fixed, no `autoscaling` block, no `management` block.
Why: two nodes was enough to run three workloads once.
Change: add `autoscaling` with a floor and a ceiling, and `management` with
`auto_repair` and `auto_upgrade`. Add `upgrade_settings` so an upgrade adds a
node before taking one away rather than the reverse.

**Anyone who can reach the API server can try to.**
Now: no `master_authorized_networks_config`, no `private_cluster_config`.
Why: the operator was on a laptop on an unknown network, and restricting access
would have meant maintaining a list of addresses for a lab.
Change: private nodes plus an authorized network list. Private nodes need a
Cloud NAT for outbound, which this estate declares and leaves commented for
exactly this moment.

**Nothing verifies what an image is.**
Now: no `binary_authorization`.
Why: images are pulled by digest, which fixes what runs but says nothing about
who built it.
Change: require attestations, which only means something once something signs
them. It is a policy, a signer and a step in whatever builds the images, and
adopting it half way is worse than not adopting it.

**The cluster's own data is encrypted with the platform's key.**
Now: no `database_encryption` block.
Why: it is on by default and the lab holds nothing.
Change: point it at a key the organization controls, so that destroying the key
destroys the contents rather than trusting a deletion.

**Only system metrics are collected and nothing says where logs go.**
Now: `monitoring_config` is declared with `SYSTEM_COMPONENTS`, `logging_config`
is not declared at all.
Why: the default enables every billable collector and the charge arrives under a
name that does not mention the cluster, so it was narrowed deliberately. That
part was right.
Change: add application metrics, declare `logging_config`, and decide retention
at ingestion rather than paying to store what nobody reads. ADR 14.

## Storage

**The ERP writes to a single pod.**
Now: an NFS server in the cluster, on a single-attach disk.
Why: a managed file service is billed on provisioned capacity with a floor far
above what one bench uses, often more than the rest of the cluster combined.
For an internal system where an hour of downtime during a node event is
acceptable, this is the right answer and the section says so.
Change: a managed file service instance, and the storage class points at it.
The deciding question is not cost, it is whether the ERP stopping for an hour
during an ordinary node upgrade is acceptable.

**The encrypted class is encrypted by the platform.**
Now: `platform/storage/encrypted-standard.yaml` uses the default key.
Why: a customer-managed key needs a key ring, a key, and a grant, and the lab
has nothing worth encrypting.
Change: create the key and add `disk-encryption-kms-key` to the class. The line
is already there, commented, with the shape of the value.

**Nothing is backed up.**
Now: no backup for the ERP's database, the automation service's database, or
the password manager's volume.
Why: nothing here is meant to survive.
Change: a backup plan for the cluster's volumes, and a schedule per database
that dumps rather than snapshots, because a snapshot of a running database is
valid often enough to be trusted and corrupt often enough to matter. Then a
restore that runs on a schedule and fails loudly, because ADR 7 is that a
backup nobody has restored is a belief.

## Identity and secrets

**Secrets are generated by the installer.**
Now: `lab/bootstrap.sh` creates them with `openssl` and applies them.
Why: it makes the environment reproducible from nothing, which is what the lab
is for.
Change: a secret manager holding them, and a driver that mounts them, so the
manifests reference rather than receive. ADR 22. Two specifics: the automation
service's encryption key must survive the cluster, because losing it costs
every stored credential even with a perfect database backup; and the ERP's
administrative password has to be set from a value taken out of the manager
rather than printed once to a terminal.

**The password manager is reachable by anyone who can resolve its name.**
Now: an ordinary route to an ordinary service.
Why: putting an identity check in front needs an identity provider, a consent
screen and a group, none of which a lab has.
Change: an identity-aware proxy in front of that backend, so an
unauthenticated request never arrives and a flaw in the application's own login
cannot be reached by a stranger. ADR 16.

## The stack itself: `lab/`

**The environment name carries a random suffix.**
Now: `suffix` is a variable appended to every project ID.
Why: a destroyed project's identifier is held for thirty days, so a lab that is
rebuilt often needs a new name each time.
Change: a real environment has a name that never changes. Remove the suffix,
and with it the ability to rebuild the same environment twice in a month, which
is a property production should not want.

**Applies happen from a laptop.**
Now: `terraform apply` run by whoever is installing.
Why: there is one operator.
Change: a pipeline that plans on a pull request and applies from the default
branch after review, which is what `docs/git-flow.md` describes and nothing
enforces.

**The probe port list is maintained by hand.**
Now: `health_check_ports` in `lab/main.tf`, with a check that refuses a
mismatch.
Why: a manifest cannot open a firewall and a firewall cannot read a manifest.
Change: nothing, probably. The coupling is real and the check makes it loud,
which is the honest treatment. It is here because it will look like an
oversight to the next reader and it is not.

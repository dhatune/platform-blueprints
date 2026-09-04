# Vaultwarden

A self-hosted password manager, deployed the way a password manager has to be
deployed.

## Why this one is different from the rest

Every other service in `platform/` can be rebuilt from backup if it breaks. This
one holds the credentials to everything else. A mistake here is not an outage,
it is a breach of every system the organisation owns.

So the deployment is not "the same recipe with a different image". Three
properties are non-negotiable, and each one is a decision that most quick-start
guides skip.

## The three that matter

**The admin panel is not reachable from the internet.** Vaultwarden ships an
admin interface that manages users and settings. Most guides protect it with a
token and expose it publicly. A token in an environment variable is a password
with no rate limit and no second factor. Here the panel is disabled outright;
administration happens through a command run against the container, by someone
who already has access to the host.

**The data is encrypted before it reaches the server, and again at rest.** The
first is Vaultwarden's own design: the server stores ciphertext it cannot read.
The second is the storage layer, and it matters because the file that holds
that ciphertext is also the file that a stolen disk image contains.

**A backup that has never been restored is not a backup.** The restore is
scripted and exercised on a schedule. Discovering that a database dump is
truncated during an incident is discovering it too late.

## Two deployments of the same service

```
deploy/     Kubernetes: namespace, deployment, volume, service, network
            policies, and a kustomization that ties them together
cloud-run/  Terraform: Cloud Run service, Cloud SQL, bucket, secrets and a
            service account holding only what it uses
backup/     backup.sh takes a consistent backup; verify-restore.sh proves
            the result is usable
```

**Cloud Run is the one to deploy.** The Kubernetes variant is kept because the
comparison is this section's actual content: seeing what the same service costs
on each platform is more useful than either manifest alone.

Both enforce the same decisions. What differs is everything underneath, and the
reason is one constraint that is easy to state imprecisely.

Cloud Run is not without persistence: a bucket can be mounted into the
container and it survives the instance. What it does not have is a filesystem
with POSIX locking. A mounted bucket presents files, not the locks a database
uses to keep two writers from interleaving. So the question is never "where do
the bytes live" but "what happens when two processes reach for them".

| | Kubernetes | Cloud Run |
|---|---|---|
| Database | SQLite on a volume | SQLite on a bucket, or a managed database |
| Held to one instance by | the volume's access mode | an explicit instance ceiling |
| Signing key | a file on the volume | mounted from a secret |
| Attachments | the same volume | a bucket mounted into the container |
| Inbound limits | network policy | ingress restricted to a load balancer |
| Outbound limits | network policy | private ranges only |
| Backups | `sqlite3 .backup` plus the verify script | managed backups and point-in-time recovery |
| Identity | a namespaced account | a service account with per-secret access |

### Two ways to run it on Cloud Run, and both are real

**Mount a bucket and keep SQLite.** This works, and it is what the author runs
in production. There is no separate database to pay for or patch, and the whole
service is one container and one bucket. The price is a ceiling written into
the configuration: the instance count is capped at exactly one, forever,
because a bucket mount gives no file locking and two writers on one SQLite file
corrupt it. Reads and writes also go through an API rather than a disk, which
is fine for a password manager and would not be for something chatty.

**Use a managed database.** More moving parts and more cost, and it removes the
ceiling: instances can come and go without the storage layer caring. Worth it
when the ceiling starts to bind, not before.

The Terraform here shows the second because the first is a smaller change from
it than the reverse, and because the ceiling deserves to be a decision somebody
makes rather than a default they inherit.

### The one that will catch you either way

The signing key. Vaultwarden generates it on first boot and uses it to sign
session tokens. If it lands on the container's own filesystem rather than in
the bucket or a secret, every new instance generates **a different key**, and a
token signed by one is rejected by the next. Users are logged out at apparently
random moments, which reads like a bug in the client rather than a consequence
of where a file lives.

The same reasoning covers attachments, which are written as files and are gone
on the next instance unless they are on the mount.

### Why Cloud Run wins here

Neither is safer. They make different mistakes easy, and the choice comes down
to which mistake you would rather be exposed to.

Kubernetes lets you keep SQLite, which is simpler and genuinely adequate here , 
but it puts the burden on you to prevent a second replica, and the enforcement
is a volume access mode and an update strategy rather than anything obvious.
Get it wrong and the database corrupts quietly.

Cloud Run takes that mistake away, because a managed database does not care how
many instances connect. In exchange it introduces a class of problem that does
not exist on the other side: state you assumed was on disk is not, and the
symptom appears far from the cause.

## The parts worth reading before copying

**`strategy: Recreate`, not `RollingUpdate`.** The database is one SQLite file
on a ReadWriteOnce volume. A rolling update starts the new pod before stopping
the old one, and for those seconds two processes hold the same database open.
Trading a few seconds of downtime for that is not a compromise, it is the only
correct setting. This service must never run a second replica.

**The backup goes through SQLite, not through the filesystem.** Copying the
file while the server runs produces something that is valid often enough to be
trusted and corrupt often enough to matter. `sqlite3 .backup` takes a read lock
and yields a file consistent as of one point in time, without stopping the
service.

**The signing keys are part of the backup.** Restore the database without them
and every session and issued token becomes invalid: the restore appears to
succeed and every user is locked out. They are small and they are the part
people forget, so the backup fails loudly when they are missing.

**Two network policies, not one.** A default-deny that selects every pod, then
an allow that names this one. A single combined policy would leave anything
later added to the namespace unconstrained; this way it fails closed.

**No `ADMIN_TOKEN`.** Vaultwarden enables its admin panel only when that
variable is set, so its absence disables the panel rather than guarding it.
ADR 6 covers why a long token at an unguessable path was not considered enough.

## What you have to supply

The manifests reference three things this repository deliberately does not
contain: a `vaultwarden-smtp` secret, a `vaultwarden-config` map holding the
domain and mail host, and a storage class that encrypts at rest. The example
names a class called `encrypted-standard`; substitute whatever your platform
provides, and confirm it actually encrypts rather than assuming it from the
name.

## Running the verification

```
backup.sh   /data /backups            # writes an archive plus its checksum
verify-restore.sh /backups/<archive>  # restores to a scratch dir and checks it
```

The second is the one that matters, and the one normally skipped. Run it on a
schedule and treat a failure as an incident. It exits non-zero on the first
failed check, touches nothing live, and reports which check failed rather than
only that something did. ADR 7 covers the reasoning.

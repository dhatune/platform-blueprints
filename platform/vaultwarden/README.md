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

## Layout

```
deploy/     Kubernetes manifests: namespace, deployment, volume, service,
            network policies, and a kustomization that ties them together
backup/     backup.sh takes a consistent backup; verify-restore.sh proves
            the result is usable
```

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

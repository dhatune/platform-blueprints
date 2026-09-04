# 7. Backups are verified by restoring them, on a schedule

**Date:** 2026-09-03
**Status:** Accepted

## Context

A backup is not a file. It is a claim that a system can be brought back, and
the claim is only tested at the moment it is needed, which is the moment it is
most expensive to find out it was false.

The specific failure this guards against is not a missing backup job. Backup
jobs are easy to write and easy to monitor, and a job that stops running is
noticed. The failure is a job that runs successfully every night and produces
files that cannot be restored. For SQLite, which is what this service uses,
there is a common and quiet version of this: copying the database file while
the server is running. The copy is usually valid. Occasionally it captures a
transaction mid-write, and the resulting file is corrupt in a way that nothing
detects until someone tries to open it.

There is a second version, less technical and more common. The database
restores perfectly and the signing keys were never included, so every session
and every issued token is invalid on restore. The restore appears to succeed
and every user is locked out.

## Decision

The backup is taken through SQLite's own `.backup` command rather than through
the filesystem, so that it is consistent as of a point in time without stopping
the service.

A separate script restores the archive into a scratch directory and checks it:
that the archive matches its checksum, that it extracts, that SQLite's
integrity check passes, that the schema is the application's rather than an
empty file, that the restored database contains users, and that the signing
keys are present. It exits non-zero on the first failure so that a scheduled
run is noticed when it fails.

The verification runs on a schedule, not only after changes to the backup
script. A backup that worked last quarter is evidence about last quarter.

## Alternatives considered

**Checking that the backup file exists and is not empty.** This is the common
default. It catches a job that stopped running and nothing else, in
particular it passes cleanly for a torn SQLite copy, which is the failure
actually worth catching.

**Stopping the service to take a cold copy.** This produces a consistent
backup with no special tooling, and for a service that can absorb the downtime
it is a defensible choice. It was rejected because `.backup` achieves the same
consistency without the outage, so the downtime buys nothing.

**Restoring into a live standby instance** rather than a scratch directory.
This verifies more, since it exercises the application against the restored
data rather than only the data itself. It was rejected as too much standing
infrastructure for the risk, and it is the natural next step if this service
ever becomes critical enough to need a recovery time objective.

## Consequences

The verification is the part that will be dropped first when it becomes
inconvenient, because it is the part that produces no output when everything is
working. Treating a failed verification as an incident, rather than as a noisy
job to be silenced, is what makes the decision hold.

The checks are deliberately specific to this application: they name its tables
and expect its signing keys. That means they must be updated if the schema
changes, and it is why they catch failures that a generic check cannot.

A verified restore still says nothing about how long a real recovery takes.
That is a separate measurement and this decision does not make it.

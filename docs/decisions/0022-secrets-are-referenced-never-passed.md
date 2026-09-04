# 22. Secrets are referenced, never passed through a deployment tool

**Date:** 2026-09-04
**Status:** Accepted

## Context

Every deployment tool offers a way to supply a password, and taking it produces
the same outcome in each of them: the tool keeps a copy somewhere nobody chose.

Two instances, found the same afternoon.

A password given to an infrastructure tool as a value is written into that
tool's state, in clear. The state then holds every credential the estate has,
is copied to whoever runs a plan, and is included in backups. The tool brought
in to keep secrets out of a repository has moved them somewhere with a weaker
access policy and no audit trail.

A password given to a deployment tool as a value is stored in that tool's
release history inside the cluster, in clear. Anyone who can read secrets in
that namespace can recover it: including the database's, including after the
person who set it has left, and it survives every upgrade because the history
does.

Neither is a bug. Both tools are storing what they were given so they can tell
what changed. The mistake is upstream: handing a credential to something whose
job is to remember.

## Decision

Secrets live in the platform's secret manager. Everything else refers to them
by name.

Containers are created as infrastructure, along with who may read each one.
**Values are never created as infrastructure.** A version is added out of band,
by a person, read from standard input so it is not in shell history either.

Access is granted per secret. A project-level grant covers every secret that
project will ever hold, including the ones added after the grant was reviewed,
which is how a service ends up able to read credentials for systems it has no
relationship with.

An application that cannot take a reference and insists on a literal value is
the thing to fix, not the rule.

## Alternatives considered

**Encrypted values committed alongside the code.** A real improvement over
plaintext and popular for good reasons: the value travels with the change that
needs it. Rejected because the decryption key becomes the secret, held by
everyone who deploys, and rotating it means re-encrypting everything at once.

**A dedicated secrets tool run in-house.** More capable than a platform's
offering, particularly for dynamic credentials. Rejected here as a component to
operate and keep available, whose own unavailability stops every deployment,
for an estate that does not need what it adds.

**Values in the deployment tool, with the state stored securely.** The
compromise most teams land on. Rejected because "stored securely" is a
statement about one location, and the credential is in the state, in the backup
of the state, and in whatever a colleague copied to debug a plan.

## Consequences

Deploying is now a two-step act: infrastructure creates the container, and
somebody puts the value in. That gap is where a first deployment fails, with an
error about an empty secret rather than about the missing step, and it will be
met by everybody once.

Rotation is a separate mechanism and this decision does not provide it. The
platform's schedule publishes a notification when a date arrives; something
else has to act on it. Setting a rotation period without building that listener
produces a secret that looks managed and is not.

And a secret read into a process is in that process's memory and in whatever it
logs. This governs where credentials are stored and who may fetch them; it says
nothing about what happens after one is fetched.

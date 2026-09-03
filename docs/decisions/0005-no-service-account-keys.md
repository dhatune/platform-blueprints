# 5. No service account keys

**Date:** 2026-09-03
**Status:** Accepted

## Context

A service account key is a static credential in a JSON file. It authenticates
whoever holds it, for as long as it exists, from anywhere.

It is also the path of least resistance. Every tutorial produces one, every
CI system accepts one, and generating one takes a single command. That is why
the decision has to be made once, at the platform level, rather than left to
whoever is unblocking a deployment at the time.

## Decision

No service account keys are generated. The modules in this repository never
create one, and the absence is stated in a comment, because missing code does
not communicate intent.

Access is obtained by:

- **Impersonation** for humans and for local tooling. An operator authenticates
  as themselves and assumes a service account for the duration of a command.
- **Workload identity federation** for systems outside the cloud provider that
  need to act on it.
- **Attached identities** for workloads inside the provider, which receive
  credentials from the metadata service and never see a file.

## Alternatives considered

**Keys with a rotation policy.** Reduces the window rather than closing it, and
depends on rotation actually happening. Rejected because the failure mode is
silent: nobody notices a key that was not rotated until it is used.

**Keys stored in a secret manager.** Better than a file on a laptop, and it
still produces a credential that works anywhere once read. The secret manager
protects storage, not use.

## Consequences

A leaked credential is bounded in time. An impersonation token expires in an
hour whether or not anyone noticed it leaked.

Access appears in the audit log as a named human assuming a role, rather than
as a service account acting with no indication of who was driving it. That
distinction is what makes an incident reviewable.

The setup is less obvious. Someone expecting to download a JSON file has to be
told why there is not one, and the first-time configuration of federation is
genuinely more work than generating a key. That cost is paid once per platform,
against a risk that is paid continuously.

An organisation policy that disables key creation is the enforcement mechanism
for this decision. It is not included in this repository, which keeps to the
hierarchy and network layout, but it is the difference between a documented
intention and a guarantee.

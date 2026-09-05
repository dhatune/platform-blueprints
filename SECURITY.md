# Security

## Reporting a vulnerability

Report privately through GitHub's advisory form on this repository
(**Security → Report a vulnerability**). It reaches the maintainer without
becoming public.

Please do not open a public issue for a vulnerability. An issue is visible to
everyone the moment it is filed, including to anyone who would use it.

Expect an acknowledgement within a week. This is a personal repository, not a
staffed product, and that timeline is what one person can honestly promise.

## What this repository is, and what that means for risk

These are blueprints. Nothing here runs as a service, holds data, or serves
users. The risk is not that this code is attacked; it is that somebody adopts
it and inherits a mistake.

That makes two classes of problem worth reporting, and the second matters more.

**A defect in what is published.** A module that grants more than it says, a
manifest that exposes something, a default that is unsafe.

**A decision that is wrong.** The documents in `docs/decisions/` argue for
specific postures. If one of them is dangerous in a case they do not mention,
that is worth more than a syntax fix, and it is the report most likely to
prevent real harm.

## What is checked automatically, and what that does not cover

Every push runs secret scanning across full history, a check that nothing
traceable to a live environment appears, type checking, tests, format and
validation for the infrastructure code, schema validation for the Kubernetes
manifests, and shell linting.

**None of that talks to a cloud API.** Applying this repository's landing zone
to a real organization found defects that every one of those checks passes: a
resource key built from values that do not exist at plan time, modules that
refused to be destroyed, an undeclared API dependency, a permission that has to
be granted above the stack, and a firewall that blocked the platform's own
health probes while reporting a healthy configuration.

Treat the automated checks as a floor. They catch a stray secret and a broken
link. They do not catch a design that does not work.

## Adopting any of this

Read the decision that accompanies a section before using it. Each one states
what it costs and what it does not protect against; those sections are the
point, and skipping them is how a blueprint becomes a liability.

Two things are deliberately absent everywhere here and should stay absent:
service account keys, and credential values inside any tool that stores what it
was given. See decisions 5 and 22.

# 6. The password manager's admin panel is disabled, not protected

**Date:** 2026-09-03
**Status:** Accepted

## Context

Vaultwarden ships an administrative interface that creates and deletes users,
changes server settings, and reads diagnostic information about the instance.
It is enabled by setting `ADMIN_TOKEN` and reached at a fixed path.

The interface is protected by that token alone. There is no second factor, no
account behind it, and no lockout: the token is a password that authenticates
whoever presents it. It is typically stored as an environment variable, which
means it appears in the deployment definition, in the process environment, and
in whatever system holds the deployment's configuration.

The usual mitigations are to make the token long, to move the panel to an
unguessable path, and to put an IP allowlist in front of it. Each of these
raises the cost of an attack without changing what a successful one yields:
administrative control of the service holding every credential the
organization owns.

## Decision

`ADMIN_TOKEN` is not set. Vaultwarden enables the panel only when the variable
is present, so leaving it unset disables the interface rather than merely
guarding it.

The operations the panel performs are done another way. User invitations go
through the normal invitation flow, which is available to organization
administrators through the ordinary authenticated interface. The rarer
operations, deleting a user, inspecting diagnostics, are performed by
executing a command against the running container, which requires cluster
access that is already governed.

## Alternatives considered

**A long token plus an unguessable path.** This is what most deployments do and
it is a real improvement over a short token at a default path. It was rejected
because it defends against scanning, which is not the threat that matters here.
A token that appears in the deployment definition is exposed by any leak of
that definition, and at that point the path is known too.

**An IP allowlist in front of the panel.** Effective, and worth having when the
panel must exist. It was rejected as the primary control because it protects
the panel's reachability rather than its authentication, and because an
allowlist is a rule that someone will widen during an incident and not narrow
afterwards.

**Keeping the panel but putting a second factor in front of it** through an
authenticating proxy. This is the strongest of the alternatives and would be
the right answer for a team that needs the panel routinely. It was rejected
here because it adds a component to protect a feature this deployment does not
need, and the cheapest way to secure a feature is not to run it.

## Consequences

Administration requires cluster access. Someone who can reach the vault's web
interface but not the cluster cannot administer the server, which is the point,
and also the cost: routine administrative work now needs a person with a higher
level of access than a web login.

Recovering from certain misconfigurations is harder. Settings normally changed
through the panel are set as environment variables and require a redeployment,
which is slower than editing a form.

This decision suits an organization small enough that administrative operations
are rare. A larger deployment, where user administration happens weekly, should
revisit it and put an authenticating proxy in front of the panel rather than
live with the friction, or worse, quietly re-enable the token.

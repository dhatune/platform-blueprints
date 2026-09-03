# Platform Blueprints

Reference implementations and architecture decisions from building and running
the technology platform of two operating businesses on Google Cloud.

This is not a tutorial collection. Each piece here answers a question I had to
answer with money and uptime on the line, and the reasoning is included because
the reasoning is the part that transfers.

---

## Why this exists

Most infrastructure examples show you the happy path and stop. They rarely say
what the decision cost, what it ruled out, or what you should do instead when
your constraints differ. That gap is where the expensive mistakes live.

So every section here carries the same three things:

- **What it does** — the working implementation.
- **Why it is built this way** — the decision and the alternative it beat.
- **What it costs** — the tradeoff you are accepting.

---

## Contents

### `patterns/llm-ports` — available now

Provider-agnostic access to language models through ports and adapters.

The application depends on a protocol, never on a vendor. Swapping providers is
a new adapter and a config change, not a rewrite. An in-memory adapter lets the
entire system be exercised in tests without a network, which is why the suite
runs in under a tenth of a second and never fails because someone else's API
had a bad afternoon.

```
49 tests offline, no sockets opened
mypy --strict, clean
5 contract tests against a real provider
```

The offline suite was green while seven defects sat in the adapter. The first
live call found all of them. Both the defects and what they taught are written
down rather than quietly fixed.

→ [Read it](patterns/llm-ports/)

### `landing-zone` — available now

The organisation layout a platform sits on: folder hierarchy, a Shared VPC host
with two physically isolated networks, and one project per product per
environment.

The environments are separate networks rather than subnets of one, and they are
not peered. There is no route between production and development to permit or
deny. That costs real money — anything shared has to be built twice — and it
buys isolation that survives someone editing a firewall rule.

```
terraform fmt -check -recursive .
terraform validate            valid
provider lock                 linux_amd64, darwin_arm64, darwin_amd64
```

→ [Read it](landing-zone/)

### `platform/vaultwarden` — available now

A password manager, deployed the way one has to be. Every other service here
can be rebuilt from backup if it breaks; this one holds the credentials to
everything else, so a mistake is a breach rather than an outage.

The admin panel is disabled rather than protected, because the token that
guards it is a password with no second factor and no lockout. The backup goes
through SQLite's own `.backup` rather than through the filesystem, because a
copy taken while the server runs is valid often enough to be trusted and
corrupt often enough to matter. And a second script restores that backup and
checks it, because a backup that has never been restored is a belief.

```
kubectl apply --dry-run    valid
restore verification       rejects a torn database, an empty one,
                           a missing signing key and a truncated archive
```

→ [Read it](platform/vaultwarden/)

### Planned

| Section | What it will cover |
|---|---|
| `platform/erpnext/` | ERPNext deployment with managed secrets, least-privilege service account, private networking and verified backups |
| `platform/chatwoot/` | Customer conversation platform, same security baseline |
| `platform/docuseal/` | Electronic signature, same security baseline |
| `platform/n8n/` | Workflow automation with credentials outside the workflow definitions |

Sections are published when they are finished, not when they are started.

---

## Ground rules

**Nothing here is copied from a live environment.** No project identifiers, no
organisation or billing identifiers, no domains, no client names. Every example
value is fictional and every credential is a placeholder.

**Secrets never reach the repository.** `.gitignore` was the first commit, the
history is scanned before every push, and configuration is expected to come from
a secret manager, not from a file.

**Comments and documentation are in English.** The code is meant to be read by
people who did not write it.

---

## Decisions

Architecture decisions live in [`docs/decisions/`](docs/decisions/). They are
short, dated, and state what was rejected as well as what was chosen.

1. [Depend on a port, not on a provider](docs/decisions/0001-depend-on-a-port-not-a-provider.md)
2. [Tests must not touch the network](docs/decisions/0002-tests-must-not-touch-the-network.md)
3. [Segregate the ports instead of widening one](docs/decisions/0003-segregated-ports-for-advanced-capabilities.md)
4. [Separate networks per environment, not one network with rules](docs/decisions/0004-isolated-networks-instead-of-one-with-rules.md)
5. [No service account keys](docs/decisions/0005-no-service-account-keys.md)
6. [The password manager's admin panel is disabled, not protected](docs/decisions/0006-no-admin-panel.md)
7. [Backups are verified by restoring them, on a schedule](docs/decisions/0007-backups-verified-by-restoring-them.md)

---

## About

Built by **Diego Hatun**.

[linkedin.com/in/dhatun](https://www.linkedin.com/in/dhatun)

Licensed under [MIT](LICENSE).

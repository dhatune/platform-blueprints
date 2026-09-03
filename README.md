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

### Planned

| Section | What it will cover |
|---|---|
| `landing-zone/` | GCP organisation layout: folder hierarchy, Shared VPC with physically isolated production and development, service projects per product, CI/CD, and a zero service-account-key posture |
| `platform/erpnext/` | ERPNext deployment with managed secrets, least-privilege service account, private networking and verified backups |
| `platform/chatwoot/` | Customer conversation platform, same security baseline |
| `platform/docuseal/` | Electronic signature, same security baseline |
| `platform/vaultwarden/` | Password manager: encryption at rest, closed admin panel, no public exposure, restore-tested backups |
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

---

## About

Built by **Diego Hatun**.

[linkedin.com/in/dhatun](https://www.linkedin.com/in/dhatun)

Licensed under [MIT](LICENSE).

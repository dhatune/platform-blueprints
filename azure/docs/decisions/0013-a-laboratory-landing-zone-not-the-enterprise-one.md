# 13. A laboratory landing zone, not the enterprise one

## Decision

This repository builds a single-subscription landing zone for one workload,
small enough to deploy in an afternoon and verify end to end. It does not
implement Microsoft's enterprise-scale Azure landing zone from the Cloud
Adoption Framework, and it is not a substitute for it.

## Alternative it beat

Starting from the enterprise-scale architecture: a management group
hierarchy, separate platform subscriptions for identity, management and
connectivity, policy initiatives assigned at management group scope, central
logging, Defender for Cloud and subscription vending, as Microsoft's
accelerator and its verified modules implement it.

Rejected for this purpose, not in general. That architecture governs an
estate of many subscriptions and teams, and most of its value appears only at
that scale. Deployed into one subscription it hides the thing this
repository exists to show: what each control in the data path actually does,
measured against Azure rather than asserted. A policy initiative of dozens of
assignments proves less, in a lab, than one assignment that a script watches
refuse a request.

## How the pieces map

| Enterprise-scale landing zone | Here |
| --- | --- |
| Management group hierarchy | None. One subscription |
| Connectivity subscription with the hub | The hub, in the same subscription as the spoke |
| Landing zone subscription per workload | One spoke |
| Policy initiatives at management group scope | Two built-in policies at subscription scope |
| Central Log Analytics and diagnostic settings everywhere | One workspace, receiving the firewall, vault and cluster audit logs; VNet flow logs to a storage account |
| Defender for Cloud | Not enabled |
| Subscription vending | Not applicable |
| Identity subscription and domain services | Not applicable: no static credentials, identities are federated |

## What it costs

An organization should not run production from this repository. The right
starting point for a real estate is Microsoft's landing zone, with this
repository's decisions and checks as a way to understand and test what the
network, identity and data-protection pieces do inside one spoke. Nothing
here claims otherwise.

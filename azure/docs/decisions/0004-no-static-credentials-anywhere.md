# 4. No static credentials anywhere

## Decision

Humans authenticate interactively. Workloads use federated workload identity. No
client secret, no certificate, no key is ever written to a file.

## Alternative it beat

A service principal with a client secret, which is the path every tutorial takes.
Rejected: a secret in a file is a secret in a backup, in a shell history and
eventually in a repository.

## What it costs

Local work requires an interactive login, so nothing runs unattended until a
pipeline exists with federated credentials of its own.

## The one exception

The storage account that receives VNet flow logs keeps shared keys enabled,
because the flow log service writes to it with the account's key. Nothing in
this repository reads or stores that key; no human or workload uses it. It is
declared in `live/lab/10-platform/main.tf` next to the account.

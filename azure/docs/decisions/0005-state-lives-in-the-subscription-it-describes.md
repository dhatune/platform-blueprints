# 5. State lives in the subscription it describes

## Decision

A storage account created by a bootstrap stack holds the state of every other
stack. The bootstrap stack keeps its own state locally.

## Alternative it beat

Local state for everything. Rejected: operating a remote backend, including its
locking and versioning, is part of what the blueprint is for.

## What it costs

If the subscription is disabled, the state goes with it. Acceptable because the
laboratory state is disposable by design and bootstrap is idempotent.

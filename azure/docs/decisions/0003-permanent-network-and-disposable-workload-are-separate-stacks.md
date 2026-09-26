# 3. Permanent network and disposable workload are separate stacks

## Decision

`10-platform` holds everything that is cheap to keep (about fifteen dollars a
month, mostly two private endpoints) and stays up. `20-workload`
holds everything that bills by the hour and is destroyed when a session ends.

## Alternative it beat

One stack destroyed and rebuilt whole. Rejected: rebuilding the network on every
session makes teardown expensive enough that it stops happening, and a forgotten
teardown is the only real threat to a fixed credit.

## What it costs

Two states to reason about, and an output contract between them that has to stay
stable.

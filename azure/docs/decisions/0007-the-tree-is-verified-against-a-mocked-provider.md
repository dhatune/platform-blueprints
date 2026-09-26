# 7. The tree is verified against a mocked provider

## Decision

Every module and stack carries a test suite that runs `terraform test` with
`mock_provider`, exercising a real plan against the provider schema without
credentials and without creating anything.

## Alternative it beat

Validating with `terraform validate` alone. Rejected: validate checks syntax and
types, and says nothing about whether a security group actually denies, whether a
route actually points at the firewall, or whether every zone is actually linked.
Those are the properties worth protecting, and they are assertable in a plan.

## What it costs

A mocked plan cannot catch what only the API knows: quota, regional availability
of a SKU, or a name already taken. Those fail on first apply and no test here
will have warned about them.

One limit that resembles those and is not one: attributes the provider computes,
a resource identifier among them, are unknown under `command = plan` and cannot
be compared. Setting `command = apply` on the run resolves them, and against a
mocked provider that still creates nothing. Reach for apply when an assertion
needs a computed value, and stay on plan otherwise, because plan is the cheaper
check and the one that fails faster.

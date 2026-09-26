# 8. A maintained built-in beats a hand-written policy

## Decision

Forbidding a public address on a network interface is enforced by assigning
Microsoft's built-in "Network interfaces should not have public IPs", looked up
by display name. This repository defines no policy of its own.

## Alternative it beat

Authoring the equivalent custom definition. A hand-written condition over an
array alias is easy to get subtly wrong: `exists` on an alias that ends in
`[*]` does not evaluate what it appears to, and the built-in expresses the
same intent with `not` and `notLike` instead. A definition with that mistake
deploys without error and enforces nothing, and no Terraform test can catch
it, because the provider never interprets the condition. Microsoft documents
the array semantics in
[Azure Policy definition structure: policy rule](https://learn.microsoft.com/en-us/azure/governance/policy/concepts/definition-structure-policy-rule)
and [Author policies for array properties](https://learn.microsoft.com/en-us/azure/governance/policy/how-to/author-policies-for-arrays).

## What it costs

A mistyped display name is also invisible to a mocked test. The difference is
how it fails: a wrong name fails loudly on the first real plan, where a wrong
condition fails silently forever. Check 7 closes the remaining gap by watching
Azure refuse a real request.

The assignment covers network interfaces only. A public address on a load
balancer is not covered by it; docs/decisions/0012 explains why this
laboratory allows none anyway.

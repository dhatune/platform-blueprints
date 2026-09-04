# 9. One workload, several entrances with different locks

**Date:** 2026-09-03
**Status:** Accepted

## Context

The automation service has three kinds of caller and they cannot share an
authentication posture.

People use the editor, and it should sit behind the organisation's single
sign-on like every other internal tool. External systems call webhooks, and
they have no identity in that sign-on — putting the webhook behind it means the
webhook stops working. Internal automation calls an API, which wants a token
rather than an interactive login.

The default arrangement is one entrance with paths behind it. That forces one
policy on all three, and the policy has to be the weakest of the three, because
the webhook cannot authenticate interactively.

## Decision

The workload is exposed through three separate service definitions pointing at
the same pods. The proxy in front attaches a different policy to each: sign-on
for the editor, none for the webhook entrance, a token check for the API.

The pods know nothing about this. The split exists so that the layer in front
has three distinct things to attach policy to.

## Alternatives considered

**One entrance, path-based rules in the proxy.** Simpler to read, and it works
where the proxy can express per-path authentication. It was rejected because it
couples the security policy to URL structure, and the application decides its
URL structure. A version that moves an endpoint moves it out from behind its
policy, silently.

**Separate deployments per posture.** The cleanest isolation, and it would allow
the webhook entrance to run with fewer permissions than the editor. It was
rejected because the instances would share one database and one encryption key,
so the isolation is mostly apparent — and it triples the operational surface for
that appearance.

## Consequences

The webhook entrance is a door with no lock in front of it. What protects it is
a token check performed inside each workflow, which means **a workflow authored
without that check is publicly callable**. That is a review rule rather than a
platform control, and review rules are weaker than platform controls.

This is stated plainly because the arrangement's real risk is that it looks
finished. Three services with three policies reads as thorough, and the gap is
in a place the diagram does not show.

Anyone adopting this should pair it with something that fails closed: a proxy
rule requiring a header the workflows set, or a periodic check that every
webhook-triggered workflow validates a token before doing anything else.

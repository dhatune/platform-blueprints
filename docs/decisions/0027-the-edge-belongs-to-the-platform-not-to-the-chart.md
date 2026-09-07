# 27. The edge belongs to the platform, not to the chart

**Date:** 2026-09-05
**Status:** Accepted

## Context

Nearly every packaged application ships with an optional entry point: turn on a
flag, supply a hostname, and the package creates the routing object itself. It
is the path of least resistance and it produces a working deployment in one
step.

It also means the hostname, the certificate and the routing for that workload
are defined inside the package's own values, in the package's own vocabulary,
which differs between packages. Ten workloads deployed that way have ten
descriptions of the same thing, and none of them are visible to whoever is
responsible for what the organization exposes.

The concrete problem is narrower than the philosophical one. The platform's
entry point applies things that do not exist in any chart's vocabulary: the
application firewall in front of a specific backend, and the health check that
has to be told which host to claim. A routing object the chart created is one
those policies do not attach to. It works, it serves traffic, and it is
unprotected in a way that looks identical to being protected.

## Decision

Charts deploy the workload and nothing else. The entry point, the certificate,
the routing and the policies attached to them are declared separately, as
platform objects, in one place per environment.

The chart's own entry point is switched off explicitly rather than left at its
default, with a comment saying why, because the next person to read the values
file will otherwise turn it on to make the service reachable.

## Alternatives considered

**Use the chart's entry point.** One object instead of two and one place to
look. Rejected because the policies that matter cannot attach to it, and
because the description of what the organization exposes ends up distributed
across every package it happens to run.

**Use the chart's entry point and attach policies to it afterward.** Possible,
since the objects are addressable once created. Rejected because it depends on
names the chart chooses, which change between chart versions with no warning
and no error: the policy stops attaching, and nothing says so.

**Wrap each chart in a thin layer that supplies the edge.** Keeps one command
per deployment. Rejected because the wrapper is a package to maintain per
workload, and the failure of the wrapper is silent in the same way.

## Consequences

Deploying a workload takes two steps and the first one alone produces something
unreachable. To anyone who has deployed the chart and nothing else, that reads
as a broken chart, and it is the most likely support question this decision
generates.

The order matters and is not enforced by anything. The routing object refers to
a service the chart creates, and applied first it sits in a state that is not
an error and not working.

What is bought is that the answer to what is exposed, on what name, with what
certificate and behind what policy, is one directory rather than an audit of
every package the organization runs.

# 13. The blast radius is the bench, not the site

**Date:** 2026-09-04
**Status:** Accepted

## Context

The framework this ERP is built on installs into a **bench**: one directory
holding the code of every application, one language runtime, and a folder per
site. Each site has its own database and its own data. Everything else is
shared — the same application code, the same runtime, the same container image.

The word for a tenant here is "site", and it behaves like one for data. A site
cannot read another site's records; backup and restore are per-site; access
control is per-site. Everything that makes a boundary feel like a boundary is
present.

It is not a boundary for anything version-shaped, and that is not obvious from
the outside. Adding an application makes it available to every site in the
bench. Upgrading the image upgrades the code under all of them simultaneously.
The version of the framework is a property of the bench, so a site needing a
newer one is asking the whole bench to move.

The way this is usually discovered: a second site is added to an existing bench
because it is cheap and the tenant boundary looks real, then something is
installed for the new site and the old one changes. Nothing warned anybody,
because from the configuration's point of view nothing about the old site was
touched.

## Decision

The bench is treated as the unit of isolation. Sites share a bench only when
they can tolerate moving together: the same framework version, the same
application versions, the same restart.

When a workload cannot accept that — a different release cadence, a
requirement that pins a version, an audience whose downtime windows do not
overlap — it gets its own bench. That means its own deployment, its own
storage, its own database, and its own image, rather than another folder in an
existing installation.

## Alternatives considered

**One bench for everything, with careful coordination.** Cheapest to run and it
works while one team owns all the sites and upgrades them together. Rejected as
a default because the coordination is invisible: nothing in the configuration
of site A mentions site B, so the constraint is carried in somebody's head and
is lost the moment that person is on holiday.

**A bench per site, always.** Complete isolation and honest boundaries. Rejected
because the fixed cost is real — each bench brings its own workers, its own
scheduler and its own shared storage — and for a handful of sites that move
together it buys isolation nobody needed.

## Consequences

Adding a site becomes a question rather than an action. That friction is the
point, and it will be resented during the first request that would have taken
five minutes.

The compatibility matrix is now a real artifact. Applications sharing a bench
must agree on the framework version, and the newest release of one is often
incompatible with the version another one needs. Choosing an older release of
an application because the bench is pinned is a normal outcome, and the reason
belongs in a comment beside the version.

Two consequences worth stating because they surface as something else:

An image change alters the filenames of static assets. The cache holds a map of
those filenames, and the map survives the deployment, so the application serves
pages referencing files that no longer exist. It looks like a broken build. The
cache service has to be restarted, not merely cleared through the application,
because the application reads the map back from it.

An upgrade runs schema migrations against every site in the bench, one after
another. That makes an upgrade a maintenance window whose length scales with
the number of sites, rather than a rollout — which is another way of saying the
bench, not the site, is the thing being deployed.

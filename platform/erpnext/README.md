# ERPNext on Kubernetes

An ERP deployed with the upstream Helm chart, which is the right way to install
it and the reason most of the interesting decisions are about what the chart
does not decide for you.

## The thing to understand before anything else

ERPNext's unit of deployment is not the site. It is the **bench**.

A bench is one installation of the framework: a directory holding the code of
every application, one language runtime, and a folder per site. Sites in the
same bench have separate databases and separate data, and they share everything
else — the same application code, the same runtime, the same container image.

That distinction decides the shape of every operational question that follows.

Adding an application makes it *available* to every site in the bench, and
installing it is then a per-site act. Upgrading the image upgrades the code
under **all** of them at once. Two sites that need different versions of the
framework do not need two sites; they need two benches.

So a site looks like a tenant boundary and is one for data. For anything
version-shaped it is not a boundary at all, and **the blast radius is the
bench**. Teams discover this by adding an application for one site and watching
another one change. See ADR 13.

## What this section contains

```
helm/    values for the upstream chart, with the choices that matter annotated
storage/ an in-cluster NFS server, and what it costs to run one
dns/     a separate zone for the hostnames a cluster publishes into, kept
         apart from the one serving the domain itself
```

The chart is not vendored here. Pinning a copy of somebody else's chart in this
repository would make it look maintained, and it would drift.

## Three things the chart will not do for you

**Create a site.** The chart deploys a bench: web workers, background workers,
scheduler, and the services they need. A site is created by running a command
against that bench, once, and it is the step people expect to be declarative
and is not. Treat it as a migration rather than as configuration.

**Choose your storage, and understand what you are choosing.** The sites
directory is written by the web process, the scheduler and every background
worker, and they do not run on the same node. It needs `ReadWriteMany`, and
there are two honest answers.

A **managed file service** is the one that survives a node dying. It is also
billed by provisioned capacity with a floor far above what a bench uses, so a
deployment holding twenty gigabytes pays for the floor — often more than the
rest of the cluster combined.

An **NFS server inside the cluster** costs one disk instead, which is roughly
two orders of magnitude less, and it works. It is what a small deployment
should probably do. What it costs is not money:

- It is a single point of failure holding state. When that pod goes, every web
  process, worker and scheduler loses its filesystem at the same instant. The
  ERP does not degrade, it stops.
- It is backed by a single-attach disk, so the pod runs on one node and moving
  it means detaching and reattaching that disk. That is minutes of downtime
  during an ordinary node upgrade, not just during a failure.
- Clients hold stale handles across a server restart. Pods that were running
  when it went away often need restarting themselves, which turns a short
  storage blip into a full restart of the deployment.
- Backups and the storage's own upgrades are now yours.

The deciding question is not cost. It is whether an hour of the ERP being down
during a node event is acceptable. For an internal system at a small company it
usually is, and the in-cluster answer is right. For anything customer-facing,
it is not, and the invoice is the cheaper problem.

**Tell you that the cache holds a map of your assets.** After the image
changes, the asset filenames change with it, and the cached map still points at
the old ones. The application serves HTML referencing files that no longer
exist and the interface loads without styling. Clearing the application cache
is not enough on its own, because the map is read back from the cache service;
that service has to be restarted. It reads as a broken deployment and it is a
stale key.

## Status

In progress. The Helm values and the decisions are here; this has not been
deployed from this repository, and that will be said plainly when it is.

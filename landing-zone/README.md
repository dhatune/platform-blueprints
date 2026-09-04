# GCP Landing Zone

The organisation layout a platform sits on: folder hierarchy, a Shared VPC host
with physically isolated environments, and one project per product per
environment.

## The problem

Most cloud accounts grow by accretion. A project is created for something
urgent, a network is added beside it, permissions are granted at the level that
makes the error go away, and two years later nobody can answer three questions:
who can reach production, what does this product cost, and what breaks if we
delete this.

A landing zone answers those three by construction rather than by audit.

## The shape

```
organisation
└── platform
    ├── shared          networking, CI/CD, observability
    └── <product>       one folder per product
        ├── prod
        └── dev
```

Two networks live in the host project and they are not connected:

```
host project
├── prod   10.10.0.0/20   ─┐
└── dev    10.20.0.0/20   ─┘  no peering, no shared routes
```

## The decisions and what they cost

**A folder per product.** An operator is granted a role on one folder instead of
on the organisation, and a mistake stops at the folder boundary. The cost is
more folders to manage and more bindings to keep track of.

**Separate networks, not subnets of one.** The common approach is one VPC split
into subnets, with firewall rules keeping environments apart. That is cheaper
to run and leaves a routed path between production and development that only a
rule prevents. Rules get edited; missing routes do not. The cost is real:
anything shared between environments has to exist twice.

**Subnet-level network access.** `compute.networkUser` is granted on a specific
subnet rather than on the host project, so a service project cannot reach a
network belonging to another product. The cost is one binding per subnet per
principal instead of one binding total.

**No service account keys, ever.** The modules never create one. A key is a
static credential that outlives the person who made it and leaves no trace once
copied. Impersonation and workload identity federation cover every case this
platform has needed. The cost is that the setup is less obvious to someone
expecting a JSON file to download.

**No Cloud NAT in the baseline.** It is only needed once a workload without an
external address must reach the public internet. Adding it beforehand opens
egress nobody asked for. Declare it when a workload requires it.

## Using it

```bash
cd example
cp terraform.tfvars.example terraform.tfvars   # then edit it
terraform init
terraform plan
```

Every value in the example is fictional. A real organisation or billing
identifier in a public repository is free reconnaissance.

## Two failures worth knowing about

**Project display names reject more than you would expect.** The accepted set is
letters, digits, hyphen, apostrophe, quote, space and exclamation mark. An em
dash or an accented character pasted from a design document is rejected by the
API. The module validates this in the plan, so it fails with a clear message
instead of a confusing one after a minute of applying.

**The provider needs an explicit quota project.** Without `billing_project` and
`user_project_override`, API calls are attributed to whichever project the
credential resolves to. It works with one project and starts failing in
confusing ways with several.

## Verification

```bash
terraform fmt -check -recursive .
cd example && terraform init -backend=false && terraform validate
```

## What is deliberately not here

No organisation policies, no logging sink to a central bucket, no budget alerts,
no Cloud NAT, and no CI/CD wiring. All of them belong in a real platform. They
are omitted so the hierarchy and the isolation decision stay legible, which is
what this section is for.

State backend configuration is present but commented: the bucket name is the
one value that cannot be made fictional and still be useful.

## Access and constraints

Two more modules complete the hierarchy, and they are different in kind.

`access` assigns roles, and every binding names a **group** rather than a
person. This is not tidiness. When someone leaves, their access has to end, and
if bindings name individuals that means finding every place their address
appears across the whole estate. Nobody does that reliably. A group makes it one
action in one place. Primitive roles are refused at plan time, and so is any
attempt to give the applying identity a role that could change IAM policy —
because an identity that can widen its own access makes the approval gate in
front of it decorative.

`guardrails` applies organisation policy constraints, which are the other kind
of control entirely. A role is a grant, and anyone who can grant roles can grant
a different one. A constraint is a limit that a project owner cannot remove. The
distinction is the difference between a decision that is written down and a
decision that holds at three in the morning when the deployment has to go out.

The constraints deny service account key creation, restrict IAM policies to the
organisation's own identities, and refuse external addresses on machines, public
database addresses and public buckets.

Two details worth knowing before applying them:

The domain restriction takes **Cloud Identity customer IDs**, not domain names.
A domain name there produces a policy that matches nothing and reports success,
which is the worst outcome a control can have. The module refuses the wrong
shape at plan time.

The constraint on automatic grants to default service accounts is correct and
will break the build process of some managed runtimes, with an error that never
mentions policy. The exception belongs at the folder holding those workloads
rather than at the organisation, so the rest of the estate keeps the protection.
That exception is configuration with a reason attached, not a change somebody
once made in a console.

Constraints are applied before access is granted. A grant made while they were
absent was never checked against them, and applying them afterwards does not
revoke it.


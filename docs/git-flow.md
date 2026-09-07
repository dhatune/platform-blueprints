# How changes move through this repository

Two things live here and they have different consequences when they are wrong.
Documents and modules are read; the `lab/` stack creates real projects, real
clusters and real DNS records and is billed by the hour. The branching model
below exists for the second kind.

## Branches

```
main              what has been applied, and what a reader should trust
develop           reviewed and agreed, not yet applied to anything
feature/<id>      work in progress, not yet reviewed
```

`main` is not "the latest code". It is a description of what exists. Somebody
asking what is deployed should be able to read `git log main` and get a true
answer, which is only possible if nothing reaches `main` before it has been
applied.

## The rule that matters

**`terraform apply` runs only from `main`, after `develop` has been merged into
it.** Never from a feature branch, never from `develop`.

Applying from anywhere else breaks the one property `main` is for. The state
then reflects a commit that may never be merged, and the next person to read
`main` is told something false with no way to notice.

## The sequence

```
1. branch from develop        feature/<id>-<short-name>
2. work, commit, push
3. pull request to develop    plan is reviewed here
4. pull request to main       the production gate
5. merge, then checkout main and pull
6. cd lab && terraform apply
```

Steps 5 and 6 are one step in intent and two in practice, and the gap between
them is where the model is usually broken: somebody merges and applies from the
branch they still have checked out.

## Commits

```
type(scope): what changed

<body: the reason, not a restatement of the diff>
```

Types are `feat`, `fix`, `docs`, `refactor`, `test`, `chore`. The subject says
what changed, not what the author did. Version tags are not created by hand,
and no commit carries the name of a tool that helped write it.

There is a discontinuity here worth stating rather than hiding. Everything
committed before this document used a plain descriptive subject and no type
prefix, and that history reads well. Adopting a machine-readable prefix buys
one thing the prose subjects cannot give: a release version derived from the
commits rather than chosen by a person. If that is not wanted here, the older
style is the better one and this section should be deleted rather than
half-followed.

## What is different for the workload sections

`platform/` holds manifests rather than state. They are applied to a cluster
that the `lab/` stack built, and applying them from a feature branch damages
nothing that outlives the lab. The discipline above still applies to what gets
merged, and the apply-only-from-main rule is specifically about infrastructure
that bills.

## Not yet in place

This is written as the intended model, and the repository does not enforce it
yet. There is no `develop` protection, no required review, and no check that
refuses an apply from the wrong branch. Naming that here is deliberate: a rule
nobody enforces is a preference, and the ones in this repository that are
enforced live in `.github/workflows/checks.yml`.

# 23. The foundation is built first, because it is the thing that gets built last

**Date:** 2026-09-04
**Status:** Accepted

## Context

The layout of an organisation, its folders, its projects, its networks, who may
do what and what is forbidden outright, is almost always the last thing anyone
thinks about. Not because it is considered and postponed, but because it is not
considered at all. Work starts with the thing that has to ship, an account is
opened, a project is created to hold it, and the estate grows outward from
there.

By the time somebody asks how the environments are separated, or which group
holds which permission, or where the audit records go, the answer is already
fixed by a series of decisions nobody made deliberately. The foundation exists.
It was just never designed.

Three consequences follow, and they arrive together.

**It does not match how the company works.** Approvals, ownership and the way
changes are reviewed exist in the organisation already. An estate that grew
outward has its own arrangement, invented per project, and the two do not meet.

**It does not match the security policy.** The policy says what must be true.
The estate says what happens to be true. Nobody compared them, because there
was no moment at which comparing them was anybody's job.

**And it does not match what the industry or the regulator expects.** Those
expectations are not exotic: separated environments, traceable access,
retained records, credentials that can be accounted for. They are hard to
satisfy afterwards, because satisfying them means changing where things already
run.

## Decision

The foundation is designed before the first workload, and designed against
three things that already exist: how the company actually operates, what its
security policy already requires, and what its industry and regulator already
expect.

That means the hierarchy, the separation between environments, the access
model and the constraints that cannot be overridden are decided first, and the
first product is deployed into them rather than beside them.

## Alternatives considered

**Start with the product and formalise later.** The default, and it is faster to
the first deployment. Rejected because "later" means moving what is already
running, which is the point at which the cost of getting it wrong is highest
and the appetite for the change is lowest.

**Adopt a vendor's reference layout wholesale.** Fast and defensible, and worth
reading. Rejected as a substitute for the work because a reference layout knows
nothing about how this company approves a change or which regulation applies to
it, and those are the parts that decide whether the layout survives contact.

## Consequences

There is a delay before anything visible ships, and it is spent on structure
nobody outside the team will ever see. That delay is real and it is the reason
this decision is usually skipped.

Some of it will be wrong. Designing a foundation before the first workload means
guessing about workloads that do not exist, and some guesses will be corrected
later at exactly the cost this decision was trying to avoid. The defence is to
decide only what is expensive to change afterwards, which is the hierarchy, the
separation and the constraints, and leave everything else open.

And a foundation that matches the company on the day it is built will drift from
it, because the company changes. This is not a thing that is done once.

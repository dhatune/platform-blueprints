# 9. A name discriminator leads, it never trails

## Decision

Where two resources derive a name from the same base and must not collide, the
distinguishing string goes at the front. The state storage account is
`"tfstate" + base`, truncated; the object repository is `"st" + base`, truncated.

## Alternative it beat

A trailing discriminator, twice. `substr("st" + base + "tf", 0, 24)` drops the
suffix exactly when names are longest. Truncating the base first,
`"st" + base[0:20] + "tf"`, looks like a fix and is not: it still equals
`"st" + base[0:22]` whenever the base carries "t" and "f" at those two positions,
which ordinary inputs reach. Both attempts passed their tests. The second was
caught only by computing a counterexample by hand rather than accepting the
reasoning.

Storage account names are globally unique in Azure, so the collision surfaces as
a baffling conflict on a second apply, in the stack whose job is to exist before
everything else.

## What it costs

Nothing, which is the point. A leading discriminator fixes character zero, so
the two names differ regardless of what the shared base contains, a guarantee
by construction rather than by reasoning about which values can occur. The two
failed attempts were both of the second kind, and that is why they failed.

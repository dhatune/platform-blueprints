# 6. The region has no default

## Decision

Every stack takes its region as a variable with no default value.

## Alternative it beat

Defaulting to a convenient region. Rejected: where data physically rests carries
legal consequences that belong to whoever operates the workload, and a default is
a decision made silently on their behalf.

## What it costs

Every deployment must supply a region explicitly. That friction is the point.

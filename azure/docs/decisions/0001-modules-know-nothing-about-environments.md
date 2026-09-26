# 1. Modules know nothing about environments

## Decision

Modules take everything that varies between environments as input: sizes,
redundancy, address plans, names. Composition in `live/` decides. The one
composition in this repository, `live/lab`, is applied for real.

## Alternative it beat

Feature flags inside the modules (`enable_ddos`, `high_availability`). Rejected:
flags produce code paths that are never exercised, and a module whose behaviour
forks six ways is a module nobody reads before changing.

## What it costs

A second environment is a second composition, not a switch. Writing one means
choosing its values deliberately, which is the point: nothing here claims to
have been tested in a configuration it was never applied in.

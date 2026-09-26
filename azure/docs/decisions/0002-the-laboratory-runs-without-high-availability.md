# 2. The laboratory runs without high availability

## Decision

Single node cluster, a single firewall instance, locally redundant storage.

## Alternative it beat

Zone redundancy at small scale. Rejected: zone redundancy is a
boolean and a replica count. Paying three times the bill to watch a boolean be
true teaches nothing.

## What it costs

Zone loss and automatic failover are never observed.
They are declared as not validated rather than assumed to work.

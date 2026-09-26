# 11. Spot is not used for the lab's node pool

## Decision

The cluster runs a single regular node pool. Spot capacity is not used
anywhere in `modules/aks`.

## Why

- **The subscription this laboratory runs on cannot use it.** Spot Virtual
  Machines are available only to Enterprise Agreement, pay-as-you-go and
  sponsored offers; a free trial is not among them
  ([About Azure Spot Virtual Machines](https://learn.microsoft.com/en-us/azure/virtual-machines/spot-vms)).
- **AKS will not run the system pool on spot.** A cluster always needs a
  regular system pool, so spot could only ever carry a second, user pool.
  Spot draws on its own quota pool, separate from regular vCPUs, so the
  limit is the offer, not the regular quota.

## What the discount would be

On the size this lab runs, `Standard_D2als_v7` in `eastus2`, spot costs
$0.014858/h against $0.0804/h on demand (catalogue, 2026-09-25): roughly
eighty-two percent off. On a supported offer, a spot user pool for
interruptible work would be worth running.

## Two traps in the catalogue

- **A spot price for a size spot does not support.** The catalogue returns a
  spot meter for `Standard_B2als_v2`, but the B-series cannot run as spot
  VMs. A price is not a promise that the product exists.
- **A "Low Priority" meter at about eighty percent off** belongs to Azure
  Batch, not to spot VMs, and AKS cannot consume it.

Read each meter together with the service it belongs to and the product's
own limits before it goes into an estimate.

## What it costs

One `Standard_D2als_v7` at the on-demand rate, $0.0804/h.

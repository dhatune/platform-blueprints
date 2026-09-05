# The lab

The stack that verifies the rest of this repository. It builds a hierarchy, a
shared network host with two isolated networks, a project and a cluster per
environment, a registry, an application firewall and the identity that changes
DNS.

It is meant to be destroyed. Nothing here should outlive the verification it
exists for.

## Where your own values go

One file, and it is not in version control.

```
cp terraform.tfvars.example terraform.tfvars
```

Then edit it. Every value the stack needs is in that file and nowhere else:

```
organization_id       your organization's numeric ID, not a domain name
billing_account       the account that gets charged
suffix                any short unique string; see below
dns_project           the project holding your public zone
dns_domain            the subtree this lab may publish into
enabled_environments  start with ["dev"]
```

**The domain.** `dns_domain` is a subtree you are willing to let a controller
write into, not the zone itself. Given `lab.example.test`, the stack publishes
under `dev.lab.example.test` and `prod.lab.example.test`, and each environment
is confined to its own. The zone that contains it is expected to already exist
in `dns_project`, and to belong to something older and more important than this
lab. ADR 26 is about exactly that.

**The suffix.** A destroyed project's identifier is held for thirty days, so a
rerun inside that window needs a value that has not been used before. It is
supplied rather than generated because a random value is unknown at plan time
and several resources here decide whether they exist at all from names derived
from it.

## Running it

Development is built and verified alone, then production is added. An
environment that is never verified on its own has not rehearsed anything, and
one that runs a smaller set of components has not rehearsed this.

```
terraform init
terraform plan -out=dev.tfplan        # enabled_environments = ["dev"]
terraform apply dev.tfplan
```

Verify, then widen the list to `["dev", "prod"]` and repeat. The second plan
also rechecks that development still matches what is written here.

## What it hands the next step

The workload sections need values this stack generates. They are outputs
rather than something to copy out of the console:

```
terraform output -json environments
```

That gives, per environment, the project, the cluster, the zone, the DNS
subtree, the identity the controllers assume, the firewall to attach, and the
command that writes a kubeconfig. `platform/edge/` says which of them goes
where.

## What it costs

Two clusters, four interruptible nodes, two load balancers once the entry
points exist, two firewall policies and their disks. The compute is the
predictable part and the rest is not, so the honest advice is to destroy it the
same day.

```
terraform destroy
```

The one thing destroy does not remove is what the record publisher wrote into
your zone, because it runs in a mode that cannot delete. Those come out by
hand, which is the cost ADR 26 accepts on purpose.

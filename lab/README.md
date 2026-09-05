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

## Building the rest of it

`terraform apply` produces a cluster and nothing running on it. One script
takes it from there:

```
./bootstrap.sh dev
```

It reads the stack's outputs, generates the manifests' values file from them,
fetches credentials, installs the certificate controller at a pinned version,
applies the edge, and waits for the certificate.

Two things it does deliberately. The values file is **generated rather than
edited**, so an environment is described in one place; a value typed in two
places is a value that will eventually disagree with itself. And the
certificate controller's version is pinned, because taking whatever is newest
means the cluster built today and the cluster built next month run different
code, and the difference surfaces when one of them behaves differently.

It is a script rather than part of the Terraform apply because the controller's
custom resources have to be registered before anything that uses them, and
because a cluster that Terraform both creates and then installs into makes one
apply that cannot be re-run when half of it fails.

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

## It is called production and it is not one

The second environment carries the same components as the first, deliberately,
so that neither is a reduced rehearsal of the other. That is a different claim
from being ready to carry a business: nothing here is backed up, secrets are
generated into the cluster rather than referenced from a manager, the ERP's
shared storage is a single pod on a single disk, and the password manager is
reachable by anyone who can resolve its name.

The full list, with what each one costs to leave alone, is in
[what this lab is not](../docs/from-the-lab-to-production.md).

## What it costs

Two clusters, four interruptible nodes and two that are not, two load balancers
once the entry points exist, two firewall policies and their disks. The compute
is the predictable part and the rest is not, so the honest advice is to destroy
it the same day.

## Taking it down

```
./teardown.sh dev
```

Not `terraform destroy` on its own, and the reason is not a shortcoming in it.
Two of the things that have to go were never created by Terraform: the load
balancer and its backend services are built by a controller inside the cluster
when a Gateway appears, and they hold a reference to the application firewall.
Terraform deletes the firewall, the platform refuses because something still
uses it, and the destroy stops with resources standing and a bill running.

The script removes the entry point first, waits for the platform to release
what it built, and then destroys the stack. The DNS zone deletes its own
records on the way out, which it has to: the publisher runs in a mode that
cannot delete them and a zone holding records cannot be deleted. ADR 26 is
about what a controller may do continuously to a zone it shares; this is an
operator destroying a zone that belongs to one environment, once, on purpose.

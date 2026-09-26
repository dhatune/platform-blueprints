# Bootstrap

Creates the storage account every other stack keeps its Terraform state in.

Run once, before anything else:

    cp terraform.tfvars.example terraform.tfvars   # fill it in
    terraform init
    terraform apply

Its own state stays local. That is not an oversight: this stack creates the
storage the others use, so it cannot keep its state there. Every resource it
declares is idempotent, so losing the local state costs an import, not a rebuild.

The account it creates is reachable over the public network, unlike the object
repository the workload uses. A state store has to be reachable from a
workstation before any private network exists.

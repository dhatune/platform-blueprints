# Laboratory platform

The permanent half of the laboratory. Networks, security groups, route tables,
private DNS zones, a key vault, an object repository, a managed identity and the
governance policies.

Everything here is cheap to keep, about fifteen dollars a month. It stays up
between working sessions, so returning
to work is one apply of `20-workload` rather than a rebuild of the estate.

    cp terraform.tfvars.example terraform.tfvars   # fill it in
    cp backend.hcl.example backend.hcl             # the outputs of live/00-bootstrap
    terraform init -backend-config=backend.hcl
    terraform apply

There is no high availability anywhere in this profile, on purpose. Zone
redundancy is a boolean and a count; it teaches nothing the code does not already
show, and it multiplies the bill.

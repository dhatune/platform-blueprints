# A minimal landing zone: hierarchy, one Shared VPC host with two isolated
# networks, and one product with a project per environment.
#
# Every value here is fictional. Replace them in terraform.tfvars, which is
# excluded from version control.

module "folders" {
  source = "../modules/folders"

  organization_id  = var.organization_id
  root_folder_name = "platform"
  product_folders  = ["storefront"]
}

module "network_host" {
  source = "../modules/shared-vpc-host"

  project_id = module.host_project.project_id
  region     = var.region

  networks = {
    prod = { subnet_cidr = "10.10.0.0/20" }
    dev  = { subnet_cidr = "10.20.0.0/20" }
  }
}

module "host_project" {
  source = "../modules/service-project"

  project_id      = "${var.project_prefix}-net-host"
  display_name    = "Network Host"
  folder_id       = module.folders.shared_folder_id
  billing_account = var.billing_account

  activate_apis = [
    "compute.googleapis.com",
    "dns.googleapis.com",
  ]
}

# One project per environment, each attached to the matching network only. The
# development project has no route to the production network because the two
# networks are not connected, not because a rule forbids it.
module "storefront" {
  source   = "../modules/service-project"
  for_each = toset(["prod", "dev"])

  project_id      = "${var.project_prefix}-storefront-${each.key}"
  display_name    = "Storefront ${each.key}"
  folder_id       = module.folders.product_folder_ids["storefront"]
  billing_account = var.billing_account

  shared_vpc_host_project = module.network_host.host_project_id

  subnet_grants = [{
    subnet_id = module.network_host.subnet_ids[each.key]
    region    = var.region
    members   = ["serviceAccount:${module.host_project.project_number}-compute@developer.gserviceaccount.com"]
  }]

  activate_apis = [
    "compute.googleapis.com",
    "run.googleapis.com",
  ]
}

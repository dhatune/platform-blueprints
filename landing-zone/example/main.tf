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

# Constraints come before access, deliberately.
#
# A grant made while the constraints are absent is a grant that was never
# checked against them, and applying them afterwards does not revoke it. The
# dependency below makes the ordering explicit rather than leaving it to
# whatever order Terraform happens to choose.
module "guardrails" {
  source = "../modules/guardrails"

  parent               = "organizations/${var.organization_id}"
  allowed_customer_ids = var.allowed_customer_ids

  # The product folder is exempted from the automatic-grants constraint
  # because its managed build process depends on those grants. The exception
  # is scoped to one folder so the rest of the estate keeps the protection.
  exempt_folders = [module.folders.product_folder_ids["storefront"]]
}

module "access" {
  source = "../modules/access"

  organization_id = var.organization_id
  folder_ids = merge(
    { shared = module.folders.shared_folder_id },
    module.folders.product_folder_ids,
  )

  # Groups, never people. Each address is a group in the directory; removing
  # someone from it removes their access everywhere, in one action.
  folder_access = {
    storefront = [
      { group = "storefront-engineers@example.test", role = "roles/run.developer" },
      { group = "storefront-engineers@example.test", role = "roles/cloudsql.client" },
      { group = "platform-operators@example.test", role = "roles/monitoring.viewer" },
    ]
    shared = [
      { group = "platform-operators@example.test", role = "roles/compute.networkViewer" },
    ]
  }

  # The applier can build the estate and cannot change who is allowed to build
  # it. Adding roles/iam.securityAdmin here would be refused at plan time.
  applier_service_account = var.applier_service_account
  applier_folder          = "shared"
  applier_roles = [
    "roles/compute.networkAdmin",
    "roles/serviceusage.serviceUsageAdmin",
  ]

  # Holds no standing member. The alert on someone being added is the control;
  # this binding is only the mechanism.
  break_glass_group = "break-glass@example.test"

  depends_on = [module.guardrails]
}

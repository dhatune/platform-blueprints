# The stack that proves the rest of this repository works.
#
# Two environments, each a physically separate network with its own project and
# its own cluster, because that is what ADR 4 argues for and a verification
# that only ever builds one has not checked the claim.
#
# Development is built and verified first, and production is the same set of
# components with the same code. An environment that runs a smaller set is not
# a rehearsal of anything.
#
# It is in the repository rather than in a scratch directory on somebody's
# laptop because a verification that cannot be repeated is an anecdote.

locals {
  # Project identifiers are held for thirty days after a project is destroyed,
  # so a fixed name can only be used once a month. The suffix makes repeated
  # runs possible.
  #
  # It is supplied rather than generated. A random value is unknown until apply,
  # and several resources here decide whether they exist at all based on names
  # derived from it, which Terraform refuses to plan. Choosing it by hand costs
  # one line in the variables file and buys a plan that can be read before it
  # is applied.
  suffix = var.suffix
  prefix = "pb-${local.suffix}"

  # The two networks never meet. Not peered, no route between them, which is
  # the whole of ADR 4: the isolation survives someone editing a firewall rule
  # because there is nothing to edit.
  # Which environments this apply builds.
  #
  # Development is applied and verified on its own first, then production is
  # added by widening this list. Staging it this way rather than with a
  # targeted apply keeps the plan honest: what is going to exist is read from
  # the configuration rather than from the command line, and the second run
  # re-checks that development still matches what is written here.
  environments = {
    for env, cfg in local.all_environments : env => cfg
    if contains(var.enabled_environments, env)
  }

  all_environments = {
    dev = {
      subnet_cidr = "10.20.0.0/20"
      pod_cidr    = "10.21.0.0/16"
      svc_cidr    = "10.22.0.0/20"
      dns_domain  = "dev.${var.dns_domain}"
    }
    prod = {
      subnet_cidr = "10.10.0.0/20"
      pod_cidr    = "10.11.0.0/16"
      svc_cidr    = "10.12.0.0/20"
      dns_domain  = "prod.${var.dns_domain}"
    }
  }

  # Every principal that has to be allowed onto a subnet, flattened so the
  # bindings can be declared outside the project module. Doing it inside would
  # make the module depend on its own output.
  subnet_members = merge([
    for env, cfg in local.environments : {
      for role in ["compute", "container"] :
      "${env}-${role}" => {
        env    = env
        member = role == "compute" ? "serviceAccount:${module.app[env].project_number}-compute@developer.gserviceaccount.com" : "serviceAccount:service-${module.app[env].project_number}@container-engine-robot.iam.gserviceaccount.com"
      }
    }
  ]...)
}

module "folders" {
  source = "../landing-zone/modules/folders"

  organization_id  = var.organization_id
  root_folder_name = "pb-lab-${local.suffix}"
  product_folders  = ["apps"]
}

module "host_project" {
  source = "../landing-zone/modules/service-project"

  project_id      = "${local.prefix}-host"
  display_name    = "PB Host"
  folder_id       = module.folders.shared_folder_id
  billing_account = var.billing_account

  activate_apis = [
    "compute.googleapis.com",
    "dns.googleapis.com",
    "container.googleapis.com",
    "artifactregistry.googleapis.com",

    # The copy of each image into the repository this estate holds runs as a
    # build inside the platform rather than on whoever is installing. ADR 12,
    # and the reason is in platform/promote-images.yaml.
    "cloudbuild.googleapis.com",
  ]
}

module "network" {
  source = "../landing-zone/modules/shared-vpc-host"

  project_id = module.host_project.project_id
  region     = var.region

  # The cluster draws pod and service addresses from the secondary ranges
  # rather than from the subnet's primary range. The pod range caps how many
  # pods the cluster can ever run and cannot be changed afterwards.
  # The ports the probes may reach, which have to be the ports the workloads
  # actually serve on.
  #
  # This is a coupling that is easy to miss and produces a failure with no
  # useful symptom. The application is healthy, the health check is configured
  # correctly, and the probe is dropped by a firewall that names neither: the
  # backend is marked unhealthy and every request gets a 503, with nothing in
  # any log connecting it to a port list in the network.
  #
  # It was found here by one workload answering on 8080, which was allowed, and
  # another on 5678, which was not.
  health_check_ports = ["80", "443", "5678", "8080"]

  networks = {
    for env, cfg in local.environments : env => {
      subnet_cidr = cfg.subnet_cidr
      secondary_ranges = {
        pods     = cfg.pod_cidr
        services = cfg.svc_cidr
      }
    }
  }
}

module "app" {
  source   = "../landing-zone/modules/service-project"
  for_each = local.environments

  project_id      = "${local.prefix}-${each.key}"
  display_name    = "PB App ${each.key}"
  folder_id       = module.folders.product_folder_ids["apps"]
  billing_account = var.billing_account

  shared_vpc_host_project = module.host_project.project_id

  activate_apis = [
    "compute.googleapis.com",
    "container.googleapis.com",
    "artifactregistry.googleapis.com",
    "secretmanager.googleapis.com",
    "iamcredentials.googleapis.com",
  ]
}

# Each project reaches its own subnet and no other. Granting on the subnet
# rather than on the host project is what stops the development cluster from
# being able to attach to the production network.
resource "google_compute_subnetwork_iam_member" "network_user" {
  for_each = local.subnet_members

  project    = module.host_project.project_id
  region     = var.region
  subnetwork = module.network.subnet_ids[each.value.env]
  role       = "roles/compute.networkUser"
  member     = each.value.member
}

# One registry, in the shared project, that both environments pull from.
#
# Built once and promoted rather than rebuilt per environment: the artifact
# production runs has to be the one development proved, and a second registry
# makes that impossible to guarantee. ADR 12 and ADR 24.
module "registry" {
  source = "../landing-zone/modules/registry"

  # The repository cannot be created until the API is enabled on the project
  # that holds it. Terraform does not infer that from a project ID passed as a
  # string, so it tries both at once and the create fails with the API
  # reporting itself disabled on a project that is enabling it.
  depends_on = [module.host_project]

  project_id = module.host_project.project_id
  region     = var.region

  repositories = {
    apps = { description = "Images this estate builds or copies at a reviewed digest." }
  }

  remote_repositories = {
    docker = {
      description = "Caching proxy for public images."
      upstream    = "docker-hub"
    }
  }

  # Read only. Nothing that runs workloads can write to the registry it pulls
  # from.
  readers = {
    apps = [
      for env in keys(local.environments) :
      "serviceAccount:${module.app[env].project_number}-compute@developer.gserviceaccount.com"
    ]
    docker = [
      for env in keys(local.environments) :
      "serviceAccount:${module.app[env].project_number}-compute@developer.gserviceaccount.com"
    ]
  }
}

module "edge_policy" {
  source   = "../landing-zone/modules/edge-policy"
  for_each = local.environments

  project_id = module.app[each.key].project_id
  name       = "${local.prefix}-${each.key}-waf"

  # Enforcing from the start, which ADR 20 argues against for a real service
  # and is right here: the point of this stack is to observe a request being
  # refused, and preview mode would only record that it would have been.
  enforcing = true
}

module "cluster" {
  source   = "../landing-zone/modules/cluster"
  for_each = local.environments

  name           = "${local.prefix}-${each.key}"
  project_id     = module.app[each.key].project_id
  project_number = module.app[each.key].project_number

  host_project_id = module.host_project.project_id
  network_id      = module.network.network_ids[each.key]
  subnet_id       = module.network.subnet_ids[each.key]

  # One zone rather than three. A regional control plane is the right default
  # for anything real and is three times the charge for a cluster that exists
  # for an afternoon.
  location = var.zone

  # Sized for three workloads at once: an ERP bench with its workers, an
  # automation service with its database, and a password manager. Two nodes
  # because a single one leaves nowhere for pods to go during an upgrade.
  machine_type = var.machine_type
  node_count   = var.node_count
  spot         = true

  deletion_protection = false

  depends_on = [google_compute_subnetwork_iam_member.network_user]
}

# The identity that changes DNS, one per environment.
#
# The zone lives in a project this stack does not own, so the grant is made
# there. That cross-project step is the one people miss: the controller is
# installed, its identity exists, and it fails with a message about the zone
# not being found rather than about access.
#
# One identity per environment rather than one shared, because the development
# cluster must not be able to write a production record. What confines each one
# to its own subtree is the controller's domain filter rather than this grant,
# which is a weakness worth naming: the permission itself is zone-wide.
resource "google_service_account" "dns" {
  for_each = local.environments

  project      = module.app[each.key].project_id
  account_id   = "sa-dns"
  display_name = "DNS records and ACME challenges"
}

resource "google_project_iam_member" "dns_admin" {
  for_each = local.environments

  project = var.dns_project
  role    = "roles/dns.admin"
  member  = "serviceAccount:${google_service_account.dns[each.key].email}"
}

# Two Kubernetes accounts share each identity: the one publishing records and
# the one answering certificate challenges. Both need exactly this permission,
# and neither holds a key. ADR 5 and ADR 25.
resource "google_service_account_iam_member" "dns_workload_identity" {
  # The identity pool is created with the cluster and does not exist before it.
  # Without this the binding is attempted first and is refused for naming a
  # pool that has not been made yet, which reads like a typo in the pool name.
  depends_on = [module.cluster]

  for_each = merge([
    for env in keys(local.environments) : {
      for sa in ["external-dns/external-dns", "cert-manager/cert-manager"] :
      "${env}-${replace(sa, "/", "-")}" => { env = env, sa = sa }
    }
  ]...)

  service_account_id = google_service_account.dns[each.value.env].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${module.app[each.value.env].project_id}.svc.id.goog[${each.value.sa}]"
}

# A zone per environment, delegated from the one that owns the domain.
#
# ADR 26 named this as the better answer and did not take it, because it needs
# control of the parent zone's delegation and that is often somebody else's.
# Here it is ours, so it is taken.
#
# What it buys is not a smaller permission, it is a smaller blast radius. The
# controller writes into a zone that contains nothing but this lab, so the
# question of what it might do to the organization's mail records stops being
# a question rather than being mitigated.
#
# It also fixes a failure that reads like a permission problem and is not: a
# domain filter narrower than the zone matches no zone at all, and the
# controller logs "no matching zone" while holding every permission it needs.
resource "google_dns_managed_zone" "environment" {
  for_each = local.environments

  project     = var.dns_project
  name        = "${local.prefix}-${each.key}"
  dns_name    = "${each.value.dns_domain}."
  description = "Names published by the ${each.key} cluster. Managed by a controller."
}

# The delegation. Without it the zone exists and nothing on the internet knows
# to ask it anything.
resource "google_dns_record_set" "delegation" {
  for_each = local.environments

  project      = var.dns_project
  managed_zone = var.dns_parent_zone
  name         = "${each.value.dns_domain}."
  type         = "NS"
  ttl          = 300
  rrdatas      = google_dns_managed_zone.environment[each.key].name_servers
}

# The build that copies images needs to write to the repository it copies into.
#
# The account is created by enabling the API, so this binding is made against a
# name that exists only after that has happened. Making it before produces a
# failure that names a principal nobody wrote.
data "google_project" "host" {
  project_id = module.host_project.project_id
}

resource "google_project_iam_member" "build_writes_images" {
  project = module.host_project.project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${data.google_project.host.number}@cloudbuild.gserviceaccount.com"

  depends_on = [module.host_project]
}

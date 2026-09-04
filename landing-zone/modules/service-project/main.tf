# A service project: one product, one environment.
#
# Separating products into their own projects makes budgets, quotas and IAM
# separable, and it means deleting a product is deleting a project rather than
# hunting for its resources.
#
# Note what this module never creates: a service account key. Keys are static
# credentials that outlive the person who made them and do not appear in any
# audit trail once copied. Workload identity federation and impersonation cover
# every case this platform has needed.

resource "google_project" "this" {
  project_id      = var.project_id
  name            = var.display_name
  folder_id       = var.folder_id
  billing_account = var.billing_account

  # Terraform should not be able to delete a project holding real data by
  # inference from a plan.
  deletion_policy = var.deletion_policy

  # Without this, an inherited default network appears with permissive rules.
  auto_create_network = false

  labels = {
    managed-by = "terraform"
  }
}

resource "google_project_service" "this" {
  for_each = toset(var.activate_apis)

  project = google_project.this.project_id
  service = each.value

  # Leave the API enabled if the resource is removed: disabling one on destroy
  # can break unrelated resources that were relying on it.
  disable_on_destroy = false
}

resource "google_compute_shared_vpc_service_project" "this" {
  count = var.shared_vpc_host_project == null ? 0 : 1

  host_project    = var.shared_vpc_host_project
  service_project = google_project.this.project_id

  depends_on = [google_project_service.this]
}

# Subnet-level access, not project-level.
#
# The keys are positional rather than descriptive, and that is deliberate.
#
# The obvious key is the subnet id paired with the member, which reads far
# better in plan output. It also cannot work: both values are usually produced
# by other resources in the same run, so neither is known when Terraform builds
# the plan, and for_each refuses a map whose keys it cannot determine yet. The
# error names for_each and unknown values without saying that the cause is the
# key expression, which sends most people looking in the wrong place.
#
# Positions are known from the configuration itself, so the map is complete at
# plan time. The cost is that reordering the list moves bindings between keys,
# which Terraform sees as destroying one and creating another. For a list of
# grants that is written once and rarely reordered, that trade is worth taking;
# a caller that reorders often should key on a name it supplies instead.
locals {
  subnet_grant_bindings = merge([
    for subnet_index, subnet in var.subnet_grants : {
      for member_index, member in subnet.members :
      "${subnet_index}-${member_index}" => {
        subnet_id = subnet.subnet_id
        region    = subnet.region
        member    = member
      }
    }
  ]...)
}

resource "google_compute_subnetwork_iam_member" "network_user" {
  for_each = local.subnet_grant_bindings

  project    = var.shared_vpc_host_project
  region     = each.value.region
  subnetwork = each.value.subnet_id
  role       = "roles/compute.networkUser"
  member     = each.value.member
}

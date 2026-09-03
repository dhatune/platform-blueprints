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
  deletion_policy = "PREVENT"

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
resource "google_compute_subnetwork_iam_member" "network_user" {
  for_each = {
    for grant in flatten([
      for subnet in var.subnet_grants : [
        for member in subnet.members : {
          key       = "${subnet.subnet_id}/${member}"
          subnet_id = subnet.subnet_id
          region    = subnet.region
          member    = member
        }
      ]
    ]) : grant.key => grant
  }

  project    = var.shared_vpc_host_project
  region     = each.value.region
  subnetwork = each.value.subnet_id
  role       = "roles/compute.networkUser"
  member     = each.value.member
}

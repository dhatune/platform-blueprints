# Shared VPC host.
#
# One host project holds every network. Products live in service projects that
# attach to it, so addressing and firewall policy are owned in one place while
# workloads, budgets and IAM stay separated per product.
#
# Each environment gets its own VPC with no peering between them. A subnet
# split inside a single network would be cheaper to run and would leave a
# routed path between production and development that only firewall rules
# prevent. A rule can be edited by mistake; a missing route cannot.

resource "google_compute_shared_vpc_host_project" "this" {
  project = var.project_id
}

resource "google_compute_network" "this" {
  for_each = var.networks

  project = var.project_id
  name    = each.key

  auto_create_subnetworks = false # Named subnets only, never the default set.
  routing_mode            = "REGIONAL"
  description             = "Isolated network for the ${each.key} environment."
}

resource "google_compute_subnetwork" "this" {
  for_each = var.networks

  project       = var.project_id
  name          = "${each.key}-${var.region}"
  region        = var.region
  network       = google_compute_network.this[each.key].id
  ip_cidr_range = each.value.subnet_cidr

  # Lets instances without external addresses reach Google APIs. Without it the
  # alternative is a NAT gateway, which costs money and widens egress.
  private_ip_google_access = true

  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# Ingress is scoped to the subnet's own range. Using the whole RFC1918 space,
# which is the common shortcut, would let any future network reach this one.
resource "google_compute_firewall" "allow_internal" {
  for_each = var.networks

  project     = var.project_id
  name        = "${each.key}-allow-internal"
  network     = google_compute_network.this[each.key].name
  description = "Allow traffic within the ${each.key} subnet only."
  direction   = "INGRESS"
  priority    = 1000

  source_ranges = [each.value.subnet_cidr]

  allow {
    protocol = "tcp"
    ports    = var.internal_ingress_ports
  }

  allow {
    protocol = "icmp"
  }
}

# Denying ingress explicitly documents the posture. GCP already defaults to
# deny, but an explicit low-priority rule survives someone adding an allow
# rule with a careless priority.
resource "google_compute_firewall" "deny_all_ingress" {
  for_each = var.networks

  project     = var.project_id
  name        = "${each.key}-deny-all-ingress"
  network     = google_compute_network.this[each.key].name
  description = "Explicit default deny for ${each.key}."
  direction   = "INGRESS"
  priority    = 65534

  source_ranges = ["0.0.0.0/0"]

  deny {
    protocol = "all"
  }
}

# A private DNS zone per network, so a name resolved in one environment cannot
# resolve to an address in the other.
resource "google_dns_managed_zone" "private" {
  for_each = var.networks

  project     = var.project_id
  name        = "${each.key}-internal"
  dns_name    = "${each.key}.internal."
  description = "Private zone for ${each.key}."
  visibility  = "private"

  private_visibility_config {
    networks {
      network_url = google_compute_network.this[each.key].id
    }
  }
}

# Cloud NAT is deliberately absent. It is only needed once a workload without
# an external address must reach the public internet, and adding it before then
# opens egress that nobody asked for. Declare it when a workload requires it,
# not as part of the baseline.

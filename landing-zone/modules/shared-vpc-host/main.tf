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

# Enabling a project as a Shared VPC host requires compute.organizations.enableXpnHost,
# which is granted by roles/compute.xpnAdmin at the organisation. Neither owner
# nor organizationAdmin includes it, so the apply fails here with a 403 that
# names the permission but not the role, and not the fact that it has to be
# granted above the folder this stack lives in.
#
# The DNS zones below need dns.googleapis.com enabled on this project. That is
# the caller's responsibility through activate_apis, and enabling an API takes
# a couple of minutes to propagate: an apply that enables it and uses it in the
# same run fails once and succeeds on retry.
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

  dynamic "secondary_ip_range" {
    for_each = each.value.secondary_ranges

    content {
      range_name    = secondary_ip_range.key
      ip_cidr_range = secondary_ip_range.value
    }
  }

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
# The platform's own health checkers have to reach the workloads, and they do
# not come from inside the subnet.
#
# Without this, a default-deny network hosts anything that talks only to itself
# and nothing at all behind a managed load balancer. The way it fails is the
# problem: the application is running, the pod answers correctly when asked
# directly, and every external request returns 503. Nothing in that picture
# points at a firewall.
#
# The addresses are fixed, published ranges belonging to the platform's probing
# infrastructure rather than to anyone else, so allowing them is narrower than
# it looks. What it does open is real: any port a workload serves becomes
# reachable from those ranges, which is why this is restricted to the ports
# that actually serve traffic rather than to everything.
resource "google_compute_firewall" "allow_health_checks" {
  for_each = var.networks

  name        = "${each.key}-allow-health-checks"
  project     = var.project_id
  network     = google_compute_network.this[each.key].name
  description = "Allow the platform's load balancer health probes into ${each.key}."
  priority    = 900

  source_ranges = var.health_check_ranges

  allow {
    protocol = "tcp"
    ports    = var.health_check_ports
  }
}

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

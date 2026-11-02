resource "google_compute_network" "vpc" {
  name                    = "vpc-aap-poc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "main" {
  name                     = "snet-aap-poc"
  network                  = google_compute_network.vpc.id
  region                   = var.region
  ip_cidr_range            = var.subnet_cidr
  private_ip_google_access = true
}

# Egress for private nodes (package repos, registries, GitHub).
resource "google_compute_router" "router" {
  name    = "rtr-aap-poc"
  network = google_compute_network.vpc.id
  region  = var.region
}

resource "google_compute_router_nat" "nat" {
  name                               = "nat-aap-poc"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# AAP web UI (platform gateway), only from the admin's public ranges.
resource "google_compute_firewall" "allow_https_admin" {
  name          = "allow-https-admin"
  network       = google_compute_network.vpc.id
  direction     = "INGRESS"
  source_ranges = var.admin_cidrs
  target_tags   = ["aap"]

  allow {
    protocol = "tcp"
    ports    = [tostring(var.gateway_https_port)]
  }
}

# Human SSH only through Identity-Aware Proxy.
resource "google_compute_firewall" "allow_iap_ssh" {
  name          = "allow-iap-ssh"
  network       = google_compute_network.vpc.id
  direction     = "INGRESS"
  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["aap", "node"]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

# Controller -> managed nodes.
resource "google_compute_firewall" "allow_aap_to_nodes" {
  name        = "allow-aap-to-nodes"
  network     = google_compute_network.vpc.id
  direction   = "INGRESS"
  source_tags = ["aap"]
  target_tags = ["node"]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

# Managed nodes -> platform (EDA event streams via gateway).
resource "google_compute_firewall" "allow_nodes_to_aap" {
  name          = "allow-nodes-to-aap"
  network       = google_compute_network.vpc.id
  direction     = "INGRESS"
  source_ranges = [var.subnet_cidr]
  target_tags   = ["aap"]

  allow {
    protocol = "tcp"
    ports    = [tostring(var.gateway_https_port)]
  }
}

# aap-01 calling its own public URL (gateway_main_url) hairpins through the
# external IP, so the source is its own public address. Needed by the installer
# health check and by any component that uses the main URL.
resource "google_compute_firewall" "allow_aap_self" {
  name          = "allow-aap-self"
  network       = google_compute_network.vpc.id
  direction     = "INGRESS"
  source_ranges = ["${google_compute_address.aap.address}/32"]
  target_tags   = ["aap"]

  allow {
    protocol = "tcp"
    ports    = [tostring(var.gateway_https_port)]
  }
}

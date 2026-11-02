locals {
  images = {
    rhel   = "rhel-cloud/rhel-9"
    ubuntu = "ubuntu-os-cloud/ubuntu-2404-lts-amd64"
  }

  # Managed nodes. Labels drive the dynamic inventory groups (env_*, app_*, os_*).
  nodes = {
    "rhel-dev-01"  = { os = "rhel", env = "dev", app = "pagos" }
    "rhel-prod-01" = { os = "rhel", env = "prod", app = "pagos" }
    "ubu-dev-01"   = { os = "ubuntu", env = "dev", app = "portal" }
  }

  ssh_metadata = {
    ssh-keys       = "${var.ssh_user}:${var.ssh_public_key}"
    enable-oslogin = "FALSE"
  }
}

resource "google_compute_address" "aap" {
  name   = "ip-aap-01"
  region = var.region
}

resource "google_compute_instance" "aap" {
  name         = "aap-01"
  machine_type = "e2-standard-4"
  zone         = var.zone
  tags         = ["aap"]

  labels = {
    env        = "shared"
    app        = "platform"
    os         = "rhel"
    managed_by = "ansible-poc"
  }

  boot_disk {
    initialize_params {
      image = local.images.rhel
      size  = 100
      type  = "pd-balanced"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.main.id
    access_config {
      nat_ip = google_compute_address.aap.address
    }
  }

  service_account {
    email  = google_service_account.aap_inventory.email
    scopes = ["cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  metadata = local.ssh_metadata

  # Allow `make stop` without Terraform seeing drift.
  desired_status = "RUNNING"
  lifecycle {
    ignore_changes = [desired_status]
  }
}

resource "google_compute_instance" "node" {
  for_each = local.nodes

  name         = each.key
  machine_type = "e2-small"
  zone         = var.zone
  tags         = ["node"]

  labels = {
    env        = each.value.env
    app        = each.value.app
    os         = each.value.os
    managed_by = "ansible-poc"
  }

  boot_disk {
    initialize_params {
      image = local.images[each.value.os]
      size  = 20
      type  = "pd-balanced"
    }
  }

  # No access_config: private only, egress through Cloud NAT.
  network_interface {
    subnetwork = google_compute_subnetwork.main.id
  }

  service_account {
    email  = google_service_account.aap_nodes.email
    scopes = ["cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  metadata = local.ssh_metadata

  desired_status = "RUNNING"
  lifecycle {
    ignore_changes = [desired_status]
  }
}

# Security invariants of the PoC network, checked on plan with a mocked provider.

mock_provider "google" {
  mock_resource "google_compute_address" {
    defaults = {
      address = "198.51.100.7"
    }
  }
}

variables {
  project_id     = "test-project"
  admin_cidrs    = ["203.0.113.10/32", "198.51.100.64/28"]
  ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITEST ansible-poc"
}

run "admin_cidrs_reject_world" {
  command = plan
  variables {
    admin_cidrs = ["0.0.0.0/0"]
  }
  expect_failures = [var.admin_cidrs]
}

run "admin_cidrs_reject_wide_range" {
  command = plan
  variables {
    admin_cidrs = ["203.0.113.10/32", "198.51.100.0/24"]
  }
  expect_failures = [var.admin_cidrs]
}

run "admin_cidrs_reject_empty" {
  command = plan
  variables {
    admin_cidrs = []
  }
  expect_failures = [var.admin_cidrs]
}

run "nodes_have_no_public_ip" {
  command = plan
  assert {
    condition     = alltrue([for n in google_compute_instance.node : length(n.network_interface[0].access_config) == 0])
    error_message = "Managed nodes must not have a public IP."
  }
}

run "aap_has_public_ip" {
  command = plan
  assert {
    condition     = length(google_compute_instance.aap.network_interface[0].access_config) == 1
    error_message = "aap-01 must expose exactly one public IP."
  }
}

run "https_only_from_admin" {
  command = plan
  assert {
    condition     = google_compute_firewall.allow_https_admin.source_ranges == toset(["203.0.113.10/32", "198.51.100.64/28"])
    error_message = "HTTPS must only be open to admin_cidrs."
  }
}

run "gateway_port_only" {
  command = plan
  assert {
    condition     = tolist(one(google_compute_firewall.allow_https_admin.allow).ports) == tolist(["443"])
    error_message = "Admin rule must open only the gateway HTTPS port."
  }
}

run "aap_self_hairpin_only_own_ip" {
  # apply against the mocked provider (no cloud calls) so computed IPs are known
  command = apply
  assert {
    condition     = google_compute_firewall.allow_aap_self.source_ranges == toset(["198.51.100.7/32"]) && tolist(one(google_compute_firewall.allow_aap_self.allow).ports) == tolist(["443"])
    error_message = "Self-access rule must allow only aap-01's own public IP on the gateway port."
  }
}

run "no_ingress_from_world" {
  # apply against the mocked provider (no cloud calls) so computed IPs are known
  command = apply
  assert {
    condition = alltrue([
      for fw in [
        google_compute_firewall.allow_https_admin,
        google_compute_firewall.allow_iap_ssh,
        google_compute_firewall.allow_aap_to_nodes,
        google_compute_firewall.allow_nodes_to_aap,
        google_compute_firewall.allow_aap_self,
      ] : !contains(tolist(coalesce(fw.source_ranges, toset([]))), "0.0.0.0/0")
    ])
    error_message = "No ingress rule may allow 0.0.0.0/0."
  }
}

run "labels_present" {
  command = plan
  assert {
    condition     = google_compute_instance.node["rhel-prod-01"].labels.env == "prod" && google_compute_instance.node["rhel-prod-01"].labels.managed_by == "ansible-poc"
    error_message = "rhel-prod-01 must carry env=prod and managed_by=ansible-poc."
  }
  assert {
    condition     = google_compute_instance.aap.labels.app == "platform"
    error_message = "aap-01 must be labelled app=platform so the inventory excludes it."
  }
}

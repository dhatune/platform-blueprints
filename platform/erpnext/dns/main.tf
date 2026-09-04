# A persistent zone for the hostnames workloads publish into.
#
# This is deliberately separate from anything a cluster creates and destroys.
# A managed zone is assigned its nameservers when it is created, and the parent
# domain delegates to those specific names. Destroying and recreating the zone
# gets a different set, which silently breaks the delegation until somebody
# updates it by hand.
#
# So the zone outlives the clusters that write into it. Records inside it are
# created and removed automatically by whatever runs in the cluster; the zone
# itself is created once and left alone.

resource "google_dns_managed_zone" "public" {
  project     = var.project_id
  name        = var.zone_name
  dns_name    = "${var.domain}."
  description = "Records published by workloads. Delegated from the parent domain."

  # Records are written by automation, so the log of who changed what is the
  # only account of why a hostname started or stopped resolving.
  cloud_logging_config {
    enable_logging = true
  }
}

# The delegation itself cannot be created here, and that is not a limitation to
# work around. The parent domain is authoritative somewhere else, and pointing
# a subdomain at these nameservers is an act performed wherever that is —
# usually a registrar's console, by a person, once.
output "delegate_these_nameservers" {
  description = <<-EOT
    Add these as NS records for the subdomain, at whatever is authoritative for
    the parent domain. Until that is done the zone exists and answers nothing:
    a zone that is not delegated is not wrong, it is simply not consulted.
  EOT
  value       = google_dns_managed_zone.public.name_servers
}

output "zone_name" {
  value = google_dns_managed_zone.public.name
}

# A separate zone for the hostnames workloads publish into.
#
# The obvious thing is to point the cluster's DNS automation at the zone that
# already serves the domain. It needs no delegation and it works immediately.
# It also hands write access to the zone holding the domain's mail records, its
# website, and everything else, to a controller that reconciles state in a loop.
#
# That controller has a mode which deletes records it does not recognize. It is
# not the default, and it is a single flag away, and the flag is set by someone
# trying to make deleted services stop resolving. A wrong filter alongside it
# removes the mail records of a company that was not deploying anything at the
# time.
#
# A delegated subdomain keeps that blast radius to hostnames that were created
# by automation in the first place. Nothing the business depends on lives in it,
# so the worst case is that services stop resolving until the controller runs
# again.
#
# The cost is one delegation, performed once by a person, and it is the whole
# argument against doing it.
#
# This zone is also deliberately separate from anything a cluster creates and
# destroys. A managed zone is assigned its nameservers at creation and the
# parent delegates to those exact names; recreating the zone gets a different
# set and the delegation points at nothing, silently, until somebody notices
# that a hostname stopped resolving.

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
# a subdomain at these nameservers is an act performed wherever that is , 
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

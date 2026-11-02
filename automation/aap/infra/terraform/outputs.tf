output "aap_public_ip" {
  description = "Public IP of the AAP web UI (reachable only from admin_cidr)."
  value       = google_compute_address.aap.address
}

output "aap_internal_ip" {
  description = "Internal IP of aap-01."
  value       = google_compute_instance.aap.network_interface[0].network_ip
}

output "evidence_bucket" {
  description = "Bucket for compliance and audit evidence."
  value       = google_storage_bucket.evidence.name
}

output "node_names" {
  description = "Managed node names."
  value       = keys(google_compute_instance.node)
}

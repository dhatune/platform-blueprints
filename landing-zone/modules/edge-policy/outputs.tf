output "policy_name" {
  description = "Name to reference when attaching this to a backend."
  value       = google_compute_security_policy.this.name
}

output "policy_id" {
  value = google_compute_security_policy.this.id
}

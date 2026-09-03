output "host_project_id" {
  description = "Project ID of the Shared VPC host."
  value       = google_compute_shared_vpc_host_project.this.project
}

output "network_ids" {
  description = "Map of environment name to network ID."
  value       = { for name, net in google_compute_network.this : name => net.id }
}

output "subnet_ids" {
  description = "Map of environment name to subnet ID, for granting service projects access."
  value       = { for name, subnet in google_compute_subnetwork.this : name => subnet.id }
}

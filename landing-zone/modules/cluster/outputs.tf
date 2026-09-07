output "name" {
  description = "Cluster name."
  value       = google_container_cluster.this.name
}

output "location" {
  description = "Zone or region the cluster runs in."
  value       = google_container_cluster.this.location
}

output "workload_pool" {
  description = "Identity pool a Kubernetes account is mapped through."
  value       = "${var.project_id}.svc.id.goog"
}

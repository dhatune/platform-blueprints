output "host_project" {
  description = "Project owning the shared networks and the registry."
  value       = module.host_project.project_id
}

output "registry" {
  description = "Registry host both environments pull from."
  value       = "${var.region}-docker.pkg.dev/${module.host_project.project_id}"
}

output "environments" {
  description = "Everything each environment needs, keyed by environment name."
  value = {
    for env in keys(local.environments) : env => {
      project             = module.app[env].project_id
      cluster             = module.cluster[env].name
      zone                = module.cluster[env].location
      dns_domain          = local.environments[env].dns_domain
      dns_service_account = google_service_account.dns[env].email
      security_policy     = module.edge_policy[env].policy_name
      credentials_command = "gcloud container clusters get-credentials ${module.cluster[env].name} --zone ${module.cluster[env].location} --project ${module.app[env].project_id}"
    }
  }
}

output "secret_ids" {
  description = "Map of secret name to its full resource id."
  value       = { for k, s in google_secret_manager_secret.this : k => s.id }
}

output "create_version_commands" {
  description = <<-EOT
    How to put a value in, without it passing through this configuration.
    Reads from standard input so the value is not in shell history either.
  EOT
  value = {
    for k, s in google_secret_manager_secret.this :
    k => "gcloud secrets versions add ${s.secret_id} --project=${var.project_id} --data-file=-"
  }
}

output "project_id" {
  description = "Project ID that was created."
  value       = google_project.this.project_id
}

output "project_number" {
  description = "Generated project number, needed for some IAM bindings."
  value       = google_project.this.number
}

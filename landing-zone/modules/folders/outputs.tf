output "root_folder_id" {
  description = "Resource name of the root folder, as folders/NNN."
  value       = google_folder.root.name
}

output "shared_folder_id" {
  description = "Resource name of the shared folder."
  value       = google_folder.shared.name
}

output "product_folder_ids" {
  description = "Map of product name to folder resource name."
  value       = { for name, folder in google_folder.product : name => folder.name }
}

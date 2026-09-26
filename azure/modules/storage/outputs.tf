output "storage_account_id" {
  description = "Account identifier, consumed by private endpoints and role assignments."
  value       = azurerm_storage_account.this.id
}

output "storage_account_name" {
  description = "Account name."
  value       = azurerm_storage_account.this.name
}

output "container_name" {
  description = "Container holding the object repository."
  value       = azurerm_storage_container.this.name
}

output "registry_id" {
  description = "Registry identifier, consumed by the private endpoint and the pull role assignment."
  value       = azurerm_container_registry.this.id
}

output "registry_name" {
  description = "Registry name."
  value       = azurerm_container_registry.this.name
}

output "login_server" {
  description = "Host a client pushes to and pulls from."
  value       = azurerm_container_registry.this.login_server
}

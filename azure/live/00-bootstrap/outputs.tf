output "state_resource_group_name" {
  description = "Resource group holding the state storage."
  value       = azurerm_resource_group.state.name
}

output "state_storage_account_name" {
  description = "Storage account other stacks configure as their backend."
  value       = azurerm_storage_account.state.name
}

output "state_container_name" {
  description = "Container other stacks configure as their backend."
  value       = azurerm_storage_container.state.name
}

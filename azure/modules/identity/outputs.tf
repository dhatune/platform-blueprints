output "identity_id" {
  description = "Resource identifier of the managed identity."
  value       = azurerm_user_assigned_identity.this.id
}

output "client_id" {
  description = "Client identifier, referenced by the Kubernetes service account annotation."
  value       = azurerm_user_assigned_identity.this.client_id
}

output "principal_id" {
  description = "Principal identifier, used as the subject of role assignments."
  value       = azurerm_user_assigned_identity.this.principal_id
}

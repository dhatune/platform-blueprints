output "key_vault_id" {
  description = "Vault identifier, consumed by private endpoints and role assignments."
  value       = azurerm_key_vault.this.id
}

output "key_vault_name" {
  description = "Vault name."
  value       = azurerm_key_vault.this.name
}

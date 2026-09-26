output "firewall_id" {
  description = "Firewall identifier."
  value       = azurerm_firewall.this.id
}

output "policy_id" {
  description = "Policy holding the rules. Child policies inherit from this one."
  value       = azurerm_firewall_policy.this.id
}

output "private_ip" {
  description = "Address the spoke's default route points at."
  value       = azurerm_firewall.this.ip_configuration[0].private_ip_address
}

output "public_ip" {
  description = "Egress address. Everything leaving the landing zone is seen as this."
  value       = azurerm_public_ip.data.ip_address
}

output "allowed_source_addresses" {
  description = "Echoes var.allowed_source_addresses, so a caller can assert the service-tag and FQDN-tag rules were actually scoped to what it intended, without reaching into the module's own policy resource."
  value       = var.allowed_source_addresses
}

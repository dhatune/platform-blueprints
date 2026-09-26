output "zone_ids" {
  description = "Private DNS zone identifiers keyed by zone name, consumed by private endpoints."
  value       = { for k, z in azurerm_private_dns_zone.this : k => z.id }
}

output "zone_names" {
  description = "Zone names that were created."
  value       = keys(azurerm_private_dns_zone.this)
}

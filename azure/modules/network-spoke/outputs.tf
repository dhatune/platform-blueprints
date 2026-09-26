output "resource_group_name" {
  description = "Resource group holding the spoke network."
  value       = azurerm_resource_group.this.name
}

output "vnet_id" {
  description = "Spoke virtual network identifier, consumed by private DNS links."
  value       = azurerm_virtual_network.this.id
}

output "vnet_name" {
  description = "Spoke virtual network name."
  value       = azurerm_virtual_network.this.name
}

output "subnet_ids" {
  description = "Subnet identifiers keyed by the logical name the caller supplied."
  value       = { for k, s in azurerm_subnet.this : k => s.id }
}

output "route_table_name" {
  description = "Route table carrying the spoke's default route."
  value       = azurerm_route_table.this.name
}

output "route_table_id" {
  description = "Identifier of that route table."
  value       = azurerm_route_table.this.id
}

output "security_group_names" {
  description = "Security group name per subnet, keyed by the same logical name as subnet_ids."
  value       = { for k, g in azurerm_network_security_group.this : k => g.name }
}

output "allow_rule_security_group_names" {
  description = <<-EOT
    Security group each allow rule actually landed in, keyed by the allow
    rule's own key (not by subnet_key). Lets a caller assert the pairing
    between what an allow rule's subnet_key names and where the rule was
    written, without reaching into the module's resource internals.
  EOT
  value       = { for k, r in azurerm_network_security_rule.allow : k => r.network_security_group_name }
}

output "allow_rule_destination_application_security_group_ids" {
  description = <<-EOT
    Destination application security groups each allow rule actually carries,
    keyed by the allow rule's own key, null for a rule that instead targets a
    destination prefix. Lets a caller assert that a rule meant to target a
    group actually does, without reaching into the module's resource
    internals.
  EOT
  value = {
    for k, r in azurerm_network_security_rule.allow :
    k => try(length(r.destination_application_security_group_ids), 0) > 0 ? r.destination_application_security_group_ids : null
  }
}


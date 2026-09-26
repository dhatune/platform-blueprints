output "resource_group_name" {
  description = "Resource group holding the hub network."
  value       = azurerm_resource_group.this.name
}

output "location" {
  description = "Region the hub was created in."
  value       = azurerm_resource_group.this.location
}

output "vnet_id" {
  description = "Hub virtual network identifier, consumed by peerings and private DNS links."
  value       = azurerm_virtual_network.this.id
}

output "vnet_name" {
  description = "Hub virtual network name, consumed by the peering declared on the hub side."
  value       = azurerm_virtual_network.this.name
}

output "firewall_subnet_id" {
  description = "Subnet the firewall attaches to."
  value       = azurerm_subnet.firewall.id
}

output "firewall_management_subnet_id" {
  description = "Subnet the firewall's management NIC attaches to. Firewall Basic requires it."
  value       = azurerm_subnet.firewall_management.id
}

# Hub network: connectivity and egress control.
#
# The hub owns the egress path and the private DNS resolution for the whole
# landing zone. Workloads never live here.

resource "azurerm_resource_group" "this" {
  name     = "rg-${var.name_prefix}-hub"
  location = var.location
  tags     = var.tags
}

resource "azurerm_virtual_network" "this" {
  name                = "vnet-${var.name_prefix}-hub"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  address_space       = var.address_space
  tags                = var.tags
}

# Azure imposes both the name and a minimum size of /26 on these two subnets.
# Neither is configurable, so neither is a variable. Only the two subnets an
# actual resource in this landing zone attaches to are declared: a bastion
# host is not part of this topology, and a reserved-but-unused subnet is a
# range nothing can ever justify later without a plan of its own.

resource "azurerm_subnet" "firewall" {
  name                 = "AzureFirewallSubnet"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [cidrsubnet(var.address_space[0], 2, 0)]
}

# Firewall Basic splits its data plane from its management plane and puts the
# second on its own NIC, in its own subnet, behind its own public IP. Azure
# fixes the name. Slot 1 of the hub space is free since this topology carries
# no bastion subnet; slot 2 is used here regardless, so the firewall subnet
# sizes stay uniform and slot 1 is left open for whatever needs it next.
resource "azurerm_subnet" "firewall_management" {
  name                 = "AzureFirewallManagementSubnet"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [cidrsubnet(var.address_space[0], 2, 2)]
}

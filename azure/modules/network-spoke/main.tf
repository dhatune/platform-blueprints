# Spoke network: where the workload lives.
#
# Azure ships a default rule at priority 65000 that ALLOWS every flow inside the
# virtual network. That is the opposite of the posture this landing zone wants,
# so each security group carries an explicit deny at priority 4000 that beats it,
# and every permitted flow is declared one by one above that line.

resource "azurerm_resource_group" "this" {
  name     = "rg-${var.name_prefix}-spoke"
  location = var.location
  tags     = var.tags
}

resource "azurerm_virtual_network" "this" {
  name                = "vnet-${var.name_prefix}-spoke"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  address_space       = var.address_space
  tags                = var.tags
}

resource "azurerm_subnet" "this" {
  for_each = var.subnets

  name                              = "snet-${each.key}"
  resource_group_name               = azurerm_resource_group.this.name
  virtual_network_name              = azurerm_virtual_network.this.name
  address_prefixes                  = [each.value.address_prefix]
  private_endpoint_network_policies = each.value.private_endpoint_network_policies
  service_endpoints                 = each.value.service_endpoints
}

resource "azurerm_network_security_group" "this" {
  for_each = var.subnets

  name                = "nsg-${var.name_prefix}-${each.key}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags
}

resource "azurerm_subnet_network_security_group_association" "this" {
  for_each = var.subnets

  subnet_id                 = azurerm_subnet.this[each.key].id
  network_security_group_id = azurerm_network_security_group.this[each.key].id
}

# The line that makes the posture real.
resource "azurerm_network_security_rule" "deny_vnet_inbound" {
  for_each = var.subnets

  name                        = "deny-vnet-inbound"
  description                 = "Overrides the Azure default that allows every intra-network flow."
  resource_group_name         = azurerm_resource_group.this.name
  network_security_group_name = azurerm_network_security_group.this[each.key].name
  priority                    = 4000
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "VirtualNetwork"
  destination_address_prefix  = "VirtualNetwork"
}

resource "azurerm_network_security_rule" "allow" {
  for_each = var.allow_rules

  name                        = each.key
  description                 = each.value.description
  resource_group_name         = azurerm_resource_group.this.name
  network_security_group_name = azurerm_network_security_group.this[each.value.subnet_key].name
  priority                    = each.value.priority
  direction                   = each.value.direction
  access                      = "Allow"
  protocol                    = each.value.protocol
  source_port_range           = "*"
  destination_port_range      = each.value.destination_port_range
  destination_port_ranges     = each.value.destination_port_ranges
  source_address_prefix       = each.value.source_address_prefix
  destination_address_prefix  = each.value.destination_address_prefix

  # Only one of these is ever non-null; the type's own validation enforces
  # it. Passing both fields unconditionally, one of them null, is how a
  # for_each over a heterogeneous map of rules stays a single resource block.
  destination_application_security_group_ids = each.value.destination_application_security_group_ids
}

# Egress leaves through the hub firewall, never straight to the internet.
# Declared with no inline route block, deliberately. An azurerm_route_table
# carrying inline route blocks owns its entire route set: any route added to
# it from elsewhere is deleted on the next apply of whichever stack owns the
# table. Keeping the default route as its own resource leaves another layer
# free to add routes without the two stacks deleting each other's on every
# apply.
resource "azurerm_route_table" "this" {
  name                          = "rt-${var.name_prefix}-spoke"
  location                      = azurerm_resource_group.this.location
  resource_group_name           = azurerm_resource_group.this.name
  bgp_route_propagation_enabled = false
  tags                          = var.tags
}

resource "azurerm_route" "default" {
  name                   = "default"
  resource_group_name    = azurerm_resource_group.this.name
  route_table_name       = azurerm_route_table.this.name
  address_prefix         = "0.0.0.0/0"
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = var.firewall_private_ip
}

# Waits for the default route, not merely for the table. AKS with
# userDefinedRouting reads the route table of the subnet it is given and
# refuses one whose default route is missing -- and now that the default
# route is a resource of its own rather than an inline block, the table can
# exist for a moment without it.
resource "azurerm_subnet_route_table_association" "this" {
  for_each = var.subnets

  subnet_id      = azurerm_subnet.this[each.key].id
  route_table_id = azurerm_route_table.this.id

  depends_on = [azurerm_route.default]
}

# A peering is two objects, one on each side. Declaring only one leaves a path
# that resolves in a single direction and fails in a way that reads like DNS.

resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  name                         = "peer-spoke-to-hub"
  resource_group_name          = azurerm_resource_group.this.name
  virtual_network_name         = azurerm_virtual_network.this.name
  remote_virtual_network_id    = var.hub_vnet_id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  use_remote_gateways          = false
}

resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  name                         = "peer-hub-to-spoke"
  resource_group_name          = var.hub_resource_group_name
  virtual_network_name         = var.hub_vnet_name
  remote_virtual_network_id    = azurerm_virtual_network.this.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  use_remote_gateways          = false
}

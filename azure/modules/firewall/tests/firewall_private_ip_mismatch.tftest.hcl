# Isolated in its own file on purpose. terraform test carries applied state
# forward between run blocks within a single file, and a computed attribute
# such as private_ip_address, once materialised by an apply, is not
# recomputed from a later run's override_resource unless the resource is
# created fresh. This file's only run is the first (and only) apply of
# azurerm_firewall.this in its own state, so the override below is guaranteed
# to be the value the mock provider actually returns.

mock_provider "azurerm" {
  mock_resource "azurerm_firewall_policy" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/firewallPolicies/afwp"
    }
  }
}

override_resource {
  target = azurerm_public_ip.data
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/publicIPAddresses/pip-data"
  }
}

override_resource {
  target = azurerm_public_ip.management
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/publicIPAddresses/pip-mgmt"
  }
}

variables {
  name_prefix              = "ops-alz-lab-eus2-01"
  location                 = "eastus2"
  resource_group_name      = "rg-ops-alz-lab-eus2-01-hub"
  subnet_id                = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/AzureFirewallSubnet"
  management_subnet_id     = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/AzureFirewallManagementSubnet"
  expected_private_ip      = "10.60.0.4"
  allowed_source_addresses = ["10.61.0.0/22"]
  tags                     = { environment = "lab" }
}

run "a_firewall_landing_on_the_wrong_address_fails_the_postcondition" {
  command = apply

  # Pin the mock to an address that deliberately disagrees with
  # var.expected_private_ip (10.60.0.4) and expect the postcondition on
  # azurerm_firewall.this to raise -- proving the guard actually catches a
  # disagreement, not merely that it stays quiet when things already match.
  override_resource {
    target = azurerm_firewall.this
    values = {
      ip_configuration = {
        name                 = "data"
        private_ip_address   = "10.60.0.99"
        public_ip_address_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/publicIPAddresses/pip-data"
        subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/AzureFirewallSubnet"
      }
    }
  }

  expect_failures = [azurerm_firewall.this]
}

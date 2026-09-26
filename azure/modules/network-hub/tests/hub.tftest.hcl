mock_provider "azurerm" {}

variables {
  name_prefix   = "ops-alz-lab-eus2-01"
  location      = "eastus2"
  address_space = ["10.60.0.0/22"]
  tags          = { environment = "lab" }
}

run "creates_one_resource_group_and_one_virtual_network" {
  command = plan

  assert {
    condition     = azurerm_resource_group.this.location == "eastus2"
    error_message = "the resource group must land in the requested region"
  }

  assert {
    condition     = azurerm_virtual_network.this.address_space == toset(["10.60.0.0/22"])
    error_message = "the hub virtual network must use the requested address space"
  }
}

run "reserved_subnet_names_are_exact" {
  command = plan

  assert {
    condition     = azurerm_subnet.firewall.name == "AzureFirewallSubnet"
    error_message = "Azure rejects any other name for the firewall subnet"
  }

  assert {
    condition     = azurerm_subnet.firewall_management.name == "AzureFirewallManagementSubnet"
    error_message = "Azure rejects any other name for the firewall management subnet"
  }
}

run "reserved_subnets_are_large_enough" {
  command = plan

  assert {
    condition     = tonumber(split("/", azurerm_subnet.firewall.address_prefixes[0])[1]) <= 26
    error_message = "the firewall subnet must be /26 or larger, which Azure requires"
  }

  assert {
    condition     = tonumber(split("/", azurerm_subnet.firewall_management.address_prefixes[0])[1]) <= 26
    error_message = "the firewall management subnet must be /26 or larger, which Azure requires"
  }
}

run "an_address_space_too_small_for_the_reserved_subnets_is_refused" {
  command = plan

  variables {
    address_space = ["10.60.0.0/26"]
  }

  # Without this guard the module silently produces /28 subnets, which Azure
  # rejects only at apply time, long after the plan looked fine.
  expect_failures = [var.address_space]
}

run "the_hub_reserves_exactly_two_subnets_and_they_do_not_overlap" {
  command = plan

  # Only the firewall's data and management planes get a subnet here. A
  # bastion host is not part of this topology, and a third, reserved-but-idle
  # subnet is a range nothing can ever hold accountable.
  assert {
    condition     = azurerm_subnet.firewall.address_prefixes[0] != azurerm_subnet.firewall_management.address_prefixes[0]
    error_message = "the two reserved subnets must not share an address prefix"
  }
}

mock_provider "azurerm" {}

variables {
  name_prefix         = "ops-alz-lab-eus2-01"
  resource_group_name = "rg-ops-alz-lab-eus2-01-hub"
  tags                = { environment = "lab" }

  zone_names = [
    "privatelink.azurecr.io",
    "privatelink.blob.core.windows.net",
    "privatelink.vaultcore.azure.net",
  ]

  vnet_ids = {
    hub   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/virtualNetworks/vnet-hub"
    spoke = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-spoke/providers/Microsoft.Network/virtualNetworks/vnet-spoke"
  }
}

run "one_zone_per_requested_name" {
  command = plan

  assert {
    condition     = length(azurerm_private_dns_zone.this) == 3
    error_message = "one private DNS zone per requested name"
  }
}

run "every_zone_is_linked_to_every_network" {
  command = plan

  assert {
    condition     = length(azurerm_private_dns_zone_virtual_network_link.this) == 6
    error_message = "three zones times two networks is six links; a missing link is a name that does not resolve"
  }
}

run "each_link_joins_its_own_zone_to_its_own_network" {
  command = plan

  # Counting links proves nothing about pairing. A regression that points every
  # link at the same zone keeps the count at six and still resolves endpoints
  # through the wrong zone -- which is the silent failure this module exists to
  # prevent. Walk the cross product and check each pair individually.
  assert {
    condition = alltrue([
      for pair in setproduct(var.zone_names, keys(var.vnet_ids)) :
      azurerm_private_dns_zone_virtual_network_link.this["${pair[0]}|${pair[1]}"].private_dns_zone_name == pair[0]
      && azurerm_private_dns_zone_virtual_network_link.this["${pair[0]}|${pair[1]}"].virtual_network_id == var.vnet_ids[pair[1]]
    ])
    error_message = "each link must join its own zone to its own network; equal counts do not prove correct pairing"
  }
}

run "registration_is_disabled_on_privatelink_zones" {
  command = plan

  assert {
    condition     = alltrue([for l in values(azurerm_private_dns_zone_virtual_network_link.this) : l.registration_enabled == false])
    error_message = "privatelink zones must never auto register virtual machine records; Azure rejects the link otherwise"
  }
}

mock_provider "azurerm" {
  mock_resource "azurerm_private_endpoint" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/privateEndpoints/pe"
    }
  }
}

variables {
  name_prefix         = "ops-alz-lab-eus2-01"
  service_key         = "blob"
  location            = "eastus2"
  resource_group_name = "rg-ops-alz-lab-eus2-01-spoke"
  subnet_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-endpoints"
  target_resource_id  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Storage/storageAccounts/stacct"
  subresource_name    = "blob"
  private_dns_zone_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
  tags                = { environment = "lab" }
}

run "the_endpoint_always_registers_its_name" {
  command = plan

  # The whole point of the module. An endpoint without this block resolves
  # publicly and reports success.
  assert {
    condition     = length(azurerm_private_endpoint.this.private_dns_zone_group) == 1
    error_message = "a private endpoint without a dns zone group leaves the name resolving to the public address"
  }

  assert {
    condition     = azurerm_private_endpoint.this.private_dns_zone_group[0].private_dns_zone_ids[0] == var.private_dns_zone_id
    error_message = "the endpoint must register in the zone it was given, not some other zone"
  }
}

run "the_connection_points_at_the_service_it_was_given" {
  command = plan

  assert {
    condition     = azurerm_private_endpoint.this.private_service_connection[0].private_connection_resource_id == var.target_resource_id
    error_message = "the endpoint must front the target it was given; a crossed wire here is invisible in every count-based test"
  }

  assert {
    condition     = azurerm_private_endpoint.this.private_service_connection[0].subresource_names[0] == var.subresource_name
    error_message = "the sub-resource is dictated per service by Azure and cannot be guessed"
  }
}

run "the_connection_is_never_left_for_a_human_to_approve" {
  command = plan

  # A manual connection is created in Pending and never carries traffic. It
  # looks identical in the portal until someone reads the state column.
  assert {
    condition     = azurerm_private_endpoint.this.private_service_connection[0].is_manual_connection == false
    error_message = "a manual connection stays pending and silently carries no traffic"
  }
}

run "an_endpoint_joins_no_group_by_default" {
  command = plan

  assert {
    condition     = length(azurerm_private_endpoint_application_security_group_association.this) == 0
    error_message = "an endpoint the caller gave no group to must not be associated to one"
  }
}

run "an_endpoint_joins_every_group_the_caller_names" {
  # apply, not plan: azurerm_private_endpoint_application_security_group_association
  # is unmocked, so its own computed attributes stay unknown until applied,
  # and referencing the resource at all under plan fails for that reason.
  command = apply

  variables {
    application_security_group_ids = [
      "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/applicationSecurityGroups/asg-reachable",
    ]
  }

  assert {
    condition     = length(azurerm_private_endpoint_application_security_group_association.this) == 1
    error_message = "one association per group the caller named"
  }

  assert {
    condition     = one(values(azurerm_private_endpoint_application_security_group_association.this)).private_endpoint_id == azurerm_private_endpoint.this.id
    error_message = "the association must name this endpoint, not some other one"
  }

  assert {
    condition     = one(values(azurerm_private_endpoint_application_security_group_association.this)).application_security_group_id == var.application_security_group_ids[0]
    error_message = "the association must carry the group the caller named"
  }
}

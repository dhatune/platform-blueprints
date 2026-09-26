mock_provider "azurerm" {
  mock_resource "azurerm_container_registry" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.ContainerRegistry/registries/acr"
    }
  }
}

variables {
  name_prefix         = "ops-alz-lab-eus2-01"
  registry_base       = "opsalzlabeus201"
  location            = "eastus2"
  resource_group_name = "rg-ops-alz-lab-eus2-01-spoke"
  tags                = { environment = "lab" }
}

run "the_registry_carries_no_static_credential" {
  command = plan

  assert {
    condition     = azurerm_container_registry.this.admin_enabled == false
    error_message = "the admin account is a username and password with push rights; pulls go by managed identity"
  }

  assert {
    condition     = azurerm_container_registry.this.anonymous_pull_enabled == false
    error_message = "anonymous pull removes access control entirely"
  }
}

run "the_registry_is_reachable_only_from_inside" {
  command = plan

  assert {
    condition     = azurerm_container_registry.this.public_network_access_enabled == false
    error_message = "with public access left on, the private endpoint is decoration"
  }
}

run "the_tier_is_the_one_the_private_endpoint_requires" {
  command = plan

  # Basic and Standard accept the configuration and then refuse the endpoint.
  assert {
    condition     = azurerm_container_registry.this.sku == "Premium"
    error_message = "a private endpoint requires the Premium tier; the lower tiers fail only when the endpoint is created"
  }
}

run "the_name_obeys_the_azure_format" {
  command = plan

  assert {
    condition     = can(regex("^[a-zA-Z0-9]{5,50}$", azurerm_container_registry.this.name))
    error_message = "a registry name is 5 to 50 letters and digits, nothing else"
  }
}

run "a_long_base_is_truncated_rather_than_rejected" {
  command = plan

  variables {
    registry_base = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  }

  assert {
    condition     = length(azurerm_container_registry.this.name) <= 50
    error_message = "the module must truncate to the Azure limit rather than let the apply fail"
  }
}

run "a_base_with_a_hyphen_is_refused_by_the_configuration" {
  command = plan

  variables {
    registry_base = "ops-alz-lab"
  }

  expect_failures = [var.registry_base]
}

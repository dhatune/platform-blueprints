mock_provider "azurerm" {}

variables {
  prefix          = "ops"
  workload        = "alz"
  environment     = "lab"
  location        = "eastus2"
  location_short  = "eus2"
  subscription_id = "00000000-0000-0000-0000-000000000000"
}

run "state_storage_keeps_every_version" {
  command = plan

  assert {
    condition     = one(azurerm_storage_account.state.blob_properties).versioning_enabled == true
    error_message = "a state file without versions gives no way back from a bad apply"
  }

  assert {
    condition     = one(one(azurerm_storage_account.state.blob_properties).delete_retention_policy).days >= 30
    error_message = "state must stay recoverable for at least thirty days"
  }
}

run "state_storage_refuses_plain_http_and_old_tls" {
  command = plan

  assert {
    condition     = azurerm_storage_account.state.https_traffic_only_enabled == true
    error_message = "state must never travel over plain HTTP"
  }

  assert {
    condition     = azurerm_storage_account.state.min_tls_version == "TLS1_2"
    error_message = "TLS below 1.2 must be refused"
  }
}

run "the_state_account_cannot_collide_with_the_object_repository" {
  command = plan

  # Every one of these inputs is admissible, and under a trailing
  # discriminator this stack and modules/storage computed the identical name:
  # staaaaaabbbbbbbbprodxytf. Asserting that the name merely ends in "tf" is
  # satisfied by the colliding name too, which is why the assertion below
  # pins where the discriminator sits rather than that it survived.
  variables {
    prefix         = "aaaaaa"
    workload       = "bbbbbbbb"
    environment    = "prod"
    location_short = "xytfzz"
  }

  assert {
    condition     = startswith(azurerm_storage_account.state.name, "tfstate")
    error_message = "the discriminator must lead the name; a trailing one is eaten by truncation and collides with the object repository"
  }

  assert {
    condition     = length(azurerm_storage_account.state.name) <= 24
    error_message = "the name must fit the Azure limit"
  }

  assert {
    condition     = can(regex("^[a-z0-9]{3,24}$", azurerm_storage_account.state.name))
    error_message = "the name must satisfy the Azure storage account format"
  }
}

run "the_state_account_refuses_anonymous_blob_access" {
  command = plan

  assert {
    condition     = azurerm_storage_account.state.allow_nested_items_to_be_public == false
    error_message = "no container in the state account may opt into public access"
  }
}

run "the_state_account_has_no_static_credential" {
  command = plan

  # Every backend block in this repository authenticates with
  # use_azuread_auth = true, so nothing ever needs the account key -- a key
  # nobody uses is a static credential kept alive for no purpose.
  assert {
    condition     = azurerm_storage_account.state.shared_access_key_enabled == false
    error_message = "the state account must not carry a shared key nothing in this repository is configured to use"
  }
}

run "the_resource_group_name_is_derived_from_the_naming_contract" {
  command = plan

  assert {
    condition     = azurerm_resource_group.state.name == "rg-ops-alz-lab-eus2-01-tfstate"
    error_message = "the group name must be built from the naming module, with the tfstate suffix"
  }
}

run "the_outputs_expose_the_resources_the_next_stack_will_use" {
  command = plan

  # The next stack configures its backend from these three. A crossed wiring
  # here is invisible until someone's state lands somewhere unexpected.
  assert {
    condition     = output.state_resource_group_name == azurerm_resource_group.state.name
    error_message = "a crossed output hands the next stack the wrong group"
  }

  assert {
    condition     = output.state_storage_account_name == azurerm_storage_account.state.name
    error_message = "a crossed output hands the next stack the wrong account"
  }

  assert {
    condition     = output.state_container_name == azurerm_storage_container.state.name
    error_message = "a crossed output hands the next stack the wrong container"
  }
}

run "the_state_container_is_private" {
  command = plan

  assert {
    condition     = azurerm_storage_container.state.container_access_type == "private"
    error_message = "a public state container would publish the whole estate"
  }
}

run "the_deployer_can_read_and_write_state_through_entra" {
  command = apply

  # Under apply the mock invents short random ids, and azurerm parses the
  # storage account id before it accepts it as a role assignment scope.
  override_resource {
    target = azurerm_storage_account.state
    values = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Storage/storageAccounts/st"
    }
  }

  override_data {
    target = data.azurerm_client_config.current
    values = {
      object_id = "33333333-3333-3333-3333-333333333333"
    }
  }

  assert {
    condition     = azurerm_role_assignment.deployer_state_data.role_definition_name == "Storage Blob Data Contributor"
    error_message = "Owner does not include the data plane; without this role the next stack's init fails with a 403"
  }

  assert {
    condition     = azurerm_role_assignment.deployer_state_data.principal_id == "33333333-3333-3333-3333-333333333333"
    error_message = "the grant must go to whoever runs Terraform, not to a fixed principal"
  }

  assert {
    condition     = azurerm_role_assignment.deployer_state_data.scope == azurerm_storage_account.state.id
    error_message = "the grant must be scoped to the state account and nothing wider"
  }
}

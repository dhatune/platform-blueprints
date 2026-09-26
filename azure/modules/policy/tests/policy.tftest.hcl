mock_provider "azurerm" {
  # azurerm parses policy_definition_id at plan time, so the placeholder the
  # mock generates on its own is rejected outright. Supply a structurally valid
  # identifier as the baseline for every lookup.
  mock_data "azurerm_policy_definition" {
    defaults = {
      id = "/providers/Microsoft.Authorization/policyDefinitions/00000000-0000-0000-0000-000000000000"
    }
  }
}

variables {
  name_prefix       = "ops-alz-lab-eus2-01"
  subscription_id   = "00000000-0000-0000-0000-000000000000"
  allowed_locations = ["eastus2"]
}

run "each_assignment_enforces_its_own_definition" {
  command = plan

  # Both lookups are the same data source type, so the provider level mock
  # cannot tell them apart. Overriding per address is what makes a crossed
  # wiring visible.
  override_data {
    target = data.azurerm_policy_definition.deny_public_nic
    values = {
      id = "/providers/Microsoft.Authorization/policyDefinitions/11111111-1111-1111-1111-111111111111"
    }
  }

  override_data {
    target = data.azurerm_policy_definition.allowed_locations
    values = {
      id = "/providers/Microsoft.Authorization/policyDefinitions/22222222-2222-2222-2222-222222222222"
    }
  }

  assert {
    condition     = azurerm_subscription_policy_assignment.deny_public_nic.policy_definition_id == "/providers/Microsoft.Authorization/policyDefinitions/11111111-1111-1111-1111-111111111111"
    error_message = "the deny assignment must enforce the interface policy, not the other definition"
  }

  assert {
    condition     = azurerm_subscription_policy_assignment.allowed_locations.policy_definition_id == "/providers/Microsoft.Authorization/policyDefinitions/22222222-2222-2222-2222-222222222222"
    error_message = "the region assignment must enforce the region policy, not the other definition"
  }
}

run "the_outputs_expose_the_right_resources" {
  # Asserting the resources is not the same as asserting the outputs: a crossed
  # output wiring leaves every resource level assertion green while handing the
  # wrong identifier to whatever consumes this module. apply is needed here
  # because assignment identifiers are unknown under plan.
  command = apply

  override_data {
    target = data.azurerm_policy_definition.deny_public_nic
    values = {
      id = "/providers/Microsoft.Authorization/policyDefinitions/11111111-1111-1111-1111-111111111111"
    }
  }

  override_data {
    target = data.azurerm_policy_definition.allowed_locations
    values = {
      id = "/providers/Microsoft.Authorization/policyDefinitions/22222222-2222-2222-2222-222222222222"
    }
  }

  assert {
    condition     = output.deny_public_nic_policy_id == "/providers/Microsoft.Authorization/policyDefinitions/11111111-1111-1111-1111-111111111111"
    error_message = "the policy id output must expose the interface policy, not the other lookup"
  }

  assert {
    condition     = output.assignment_ids["deny_public_nic"] == azurerm_subscription_policy_assignment.deny_public_nic.id
    error_message = "each key of the assignment map must carry its own assignment identifier"
  }

  assert {
    condition     = output.assignment_ids["allowed_locations"] == azurerm_subscription_policy_assignment.allowed_locations.id
    error_message = "each key of the assignment map must carry its own assignment identifier"
  }
}

run "the_region_restriction_carries_the_regions_it_was_given" {
  command = plan

  assert {
    condition     = tolist(jsondecode(azurerm_subscription_policy_assignment.allowed_locations.parameters).listOfAllowedLocations.value) == tolist(var.allowed_locations)
    error_message = "an assignment whose parameters are empty or wrong restricts nothing, which is the whole point of this policy"
  }
}

run "the_region_restriction_follows_a_multi_region_caller" {
  command = plan

  # The run above passes even against a hardcoded parameter, because the
  # default fixture happens to match it. Only a second, different caller
  # proves the parameter is derived rather than fixed.
  variables {
    allowed_locations = ["eastus2", "westus3"]
  }

  assert {
    condition     = length(jsondecode(azurerm_subscription_policy_assignment.allowed_locations.parameters).listOfAllowedLocations.value) == 2
    error_message = "the allowed region list must be derived from the caller, not fixed in the module"
  }
}

run "both_policies_are_assigned_to_the_subscription" {
  command = plan

  assert {
    condition     = azurerm_subscription_policy_assignment.deny_public_nic.subscription_id == "/subscriptions/00000000-0000-0000-0000-000000000000"
    error_message = "the assignment must target the subscription scope"
  }

  assert {
    condition     = azurerm_subscription_policy_assignment.allowed_locations.subscription_id == "/subscriptions/00000000-0000-0000-0000-000000000000"
    error_message = "region restriction is what keeps data out of an unintended jurisdiction"
  }
}

run "assignment_names_carry_the_deployment_prefix" {
  command = plan

  assert {
    condition     = azurerm_subscription_policy_assignment.deny_public_nic.name == "ops-alz-lab-eus2-01-deny-public-nic"
    error_message = "a fixed name collides with any other landing zone in the same subscription"
  }

  assert {
    condition     = azurerm_subscription_policy_assignment.allowed_locations.name == "ops-alz-lab-eus2-01-allowed-locations"
    error_message = "a fixed name collides with any other landing zone in the same subscription"
  }
}

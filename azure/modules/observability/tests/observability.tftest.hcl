mock_provider "azurerm" {
  mock_resource "azurerm_log_analytics_workspace" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ops-alz-lab-eus2-01-spoke/providers/Microsoft.OperationalInsights/workspaces/log-ops-alz-lab-eus2-01"
    }
  }
}

variables {
  name_prefix         = "ops-alz-lab-eus2-01"
  location            = "eastus2"
  resource_group_name = "rg-ops-alz-lab-eus2-01-spoke"
  tags                = { environment = "lab" }
}

run "the_workspace_uses_the_only_sku_azure_still_sells" {
  command = plan

  assert {
    condition     = azurerm_log_analytics_workspace.this.sku == "PerGB2018"
    error_message = "the legacy per-node and capacity-reservation tiers are closed to new workspaces"
  }
}

run "retention_defaults_to_the_azure_floor" {
  command = plan

  # A lab does not need history, and retention is the line on this resource
  # that actually costs money -- the default must not creep upward silently.
  assert {
    condition     = azurerm_log_analytics_workspace.this.retention_in_days == 30
    error_message = "the default retention must be the Azure minimum, not a larger value chosen for convenience"
  }
}

run "a_retention_below_the_azure_floor_is_refused" {
  command = plan

  variables {
    retention_in_days = 29
  }

  expect_failures = [var.retention_in_days]
}

run "a_retention_above_the_azure_ceiling_is_refused" {
  command = plan

  variables {
    retention_in_days = 731
  }

  expect_failures = [var.retention_in_days]
}

run "the_workspace_name_carries_the_shared_prefix" {
  command = plan

  assert {
    condition     = azurerm_log_analytics_workspace.this.name == "log-ops-alz-lab-eus2-01"
    error_message = "the workspace name must be built from name_prefix, not a literal"
  }
}

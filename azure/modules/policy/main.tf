# Governance as code.
#
# Note what this module does NOT do: it defines no policy of its own. Forbidding
# a workload a public address means matching a network interface that carries
# one, and expressing that requires an Azure Policy alias written by hand. An
# alias with one wrong character deploys without error and enforces nothing, and
# no test against a mocked provider can tell -- it is semantics inside a JSON
# string the provider never interprets.
#
# Microsoft maintains that exact policy as a built-in, so this module assigns it
# instead of copying it. Looking a built-in up by display name carries its own
# risk, but a wrong name fails loudly on the first real plan, where a wrong alias
# fails silently forever. That asymmetry is the decision.
#
# Both lookups are by display name rather than by identifier, so no opaque GUID
# is written into the code.

data "azurerm_policy_definition" "deny_public_nic" {
  display_name = "Network interfaces should not have public IPs"
}

data "azurerm_policy_definition" "allowed_locations" {
  display_name = "Allowed locations"
}

resource "azurerm_subscription_policy_assignment" "deny_public_nic" {
  name                 = "${var.name_prefix}-deny-public-nic"
  display_name         = "Network interfaces must not carry a public IP address"
  description          = "Workloads reach the internet through the egress path, never through an address of their own."
  subscription_id      = "/subscriptions/${var.subscription_id}"
  policy_definition_id = data.azurerm_policy_definition.deny_public_nic.id
}

resource "azurerm_subscription_policy_assignment" "allowed_locations" {
  name                 = "${var.name_prefix}-allowed-locations"
  display_name         = "Resources may only be created in approved regions"
  subscription_id      = "/subscriptions/${var.subscription_id}"
  policy_definition_id = data.azurerm_policy_definition.allowed_locations.id

  parameters = jsonencode({
    listOfAllowedLocations = {
      value = var.allowed_locations
    }
  })
}

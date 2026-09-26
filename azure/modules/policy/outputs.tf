output "deny_public_nic_policy_id" {
  description = "Identifier of the built-in this module assigns, referenced when checking compliance."
  value       = data.azurerm_policy_definition.deny_public_nic.id
}

output "assignment_ids" {
  description = "Policy assignment identifiers keyed by a short name."
  value = {
    deny_public_nic   = azurerm_subscription_policy_assignment.deny_public_nic.id
    allowed_locations = azurerm_subscription_policy_assignment.allowed_locations.id
  }
}

output "deny_public_nic_assignment_name" {
  description = "Name Azure cites when this assignment refuses a request. Check 7 requires it."
  value       = azurerm_subscription_policy_assignment.deny_public_nic.name
}

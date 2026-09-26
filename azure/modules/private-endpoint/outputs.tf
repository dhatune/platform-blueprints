output "private_endpoint_id" {
  description = "Endpoint identifier."
  value       = azurerm_private_endpoint.this.id
}

output "private_ip" {
  description = "Address the service now answers on inside the network."
  value       = azurerm_private_endpoint.this.private_service_connection[0].private_ip_address
}

# Echo-backs of the module's own inputs. A stack test cannot reach inside a
# child module's resources, and a stack that instantiates this module more
# than once (one endpoint per private-linked service) has no other way to
# assert which endpoint fronts which service. Without these, a crossed wire
# between two instances -- endpoint A wired to endpoint B's target and zone,
# and vice versa -- leaves every count still matching and both names
# unresolvable, and nothing in a stack test can tell the difference.

output "target_resource_id" {
  description = "Echoes var.target_resource_id, so a caller composing this module twice can assert which endpoint targets which service."
  value       = var.target_resource_id
}

output "private_dns_zone_id" {
  description = "Echoes var.private_dns_zone_id, so a caller composing this module twice can assert which endpoint registers in which zone."
  value       = var.private_dns_zone_id
}

output "application_security_group_ids" {
  description = "Echoes var.application_security_group_ids, so a caller can assert which endpoints joined the group and which deliberately did not."
  value       = var.application_security_group_ids
}

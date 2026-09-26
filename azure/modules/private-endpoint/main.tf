# One private endpoint, with the DNS registration that makes it useful.
#
# An endpoint without a zone group is the quietest failure in Azure
# networking: the resource is created, the connection is approved, and the
# client keeps resolving the service's public address. Nothing errors. The
# zone group is therefore not optional in this module.
#
# The module is deliberately generic: it takes the target, sub-resource and
# zone as inputs rather than assuming which service it fronts, so the same
# module instantiates once per private-linked service in the stack.

resource "azurerm_private_endpoint" "this" {
  name                = "pe-${var.name_prefix}-${var.service_key}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-${var.service_key}"
    private_connection_resource_id = var.target_resource_id
    subresource_names              = [var.subresource_name]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [var.private_dns_zone_id]
  }
}

# Joins this endpoint to whichever application security groups the caller
# named, so a network security rule elsewhere can target the group as a
# destination rather than the whole subnet. Requires the endpoint's subnet to
# carry private_endpoint_network_policies = Enabled -- Disabled bypasses the
# subnet's security groups (and therefore this association) entirely.
#
# Keyed by index, not by toset() over the group ids themselves. A caller
# building this list from a resource this module does not own -- an
# application security group created alongside the stack that composes this
# module -- passes an id that is not known until that resource is applied,
# and for_each requires its own key set to be known at plan even when the
# values behind those keys are not. The list's own length is known from the
# expression that builds it, which is all an index-keyed map needs.
resource "azurerm_private_endpoint_application_security_group_association" "this" {
  for_each = { for idx, group_id in var.application_security_group_ids : tostring(idx) => group_id }

  private_endpoint_id           = azurerm_private_endpoint.this.id
  application_security_group_id = each.value
}

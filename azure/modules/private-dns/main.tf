# Private DNS: the half of private networking that is easy to forget.
#
# A private endpoint without a zone linked to the calling network still resolves
# to the public address of the service. Nothing errors. Traffic simply leaves the
# way it was not supposed to, and the symptom looks like a firewall problem.

resource "azurerm_private_dns_zone" "this" {
  for_each = toset(var.zone_names)

  name                = each.value
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

locals {
  # One link per zone per network.
  links = {
    for pair in setproduct(var.zone_names, keys(var.vnet_ids)) :
    "${pair[0]}|${pair[1]}" => {
      zone_name = pair[0]
      vnet_key  = pair[1]
    }
  }
}

resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  for_each = local.links

  name                  = "link-${var.name_prefix}-${each.value.vnet_key}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.this[each.value.zone_name].name
  virtual_network_id    = var.vnet_ids[each.value.vnet_key]

  # Auto registration is for zones that hold virtual machine records. Azure
  # rejects it on privatelink zones.
  registration_enabled = false

  tags = var.tags
}

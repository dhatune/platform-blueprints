# Container registry.
#
# Premium is not a choice here: the private endpoint requires it. The lab
# therefore runs the registry at the same tier a production deployment would.

resource "azurerm_container_registry" "this" {
  name                = substr("acr${var.registry_base}", 0, 50)
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "Premium"
  tags                = var.tags

  # The admin account is a username and a password. Enabling it would hand any
  # holder of those two strings full push rights, and it is exactly the static
  # credential this landing zone exists to avoid. Pulls happen by managed
  # identity.
  admin_enabled = false

  # Reachable only through the private endpoint. Without this the registry
  # answers on the internet and the endpoint is decoration.
  public_network_access_enabled = false

  # A registry that serves anonymous pulls has no access control worth the
  # name, and the setting defaults differently across SKUs.
  anonymous_pull_enabled = false
}

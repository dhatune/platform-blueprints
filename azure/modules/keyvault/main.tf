# Secret store.
#
# Two properties matter more than the rest. Purge protection means a deletion
# can always be undone, which is the difference between an incident and a loss.
# Role based authorisation means permissions live in the same place as every
# other permission, instead of in a second parallel system nobody reviews.
#
# Know before you apply this to a real subscription: purge protection is a
# one way switch. Once enabled on a vault it cannot be turned off, and the
# vault cannot be permanently removed until its retention window elapses. That
# is the point -- it is what stops an attacker, or a mistake, from destroying
# keys outright -- but it is inherited, not chosen, by whoever comes next.

resource "azurerm_key_vault" "this" {
  name                = substr("kv-${var.name_prefix}", 0, 24)
  resource_group_name = var.resource_group_name
  location            = var.location
  tenant_id           = var.tenant_id
  sku_name            = var.sku_name

  rbac_authorization_enabled = true
  purge_protection_enabled   = true
  soft_delete_retention_days = var.soft_delete_retention_days

  # Closed to the public network. Whether anything at all gets around the deny
  # below is the caller's explicit decision, not a default buried here.
  public_network_access_enabled = var.public_network_access_enabled

  network_acls {
    default_action = "Deny"
    bypass         = var.network_bypass
    ip_rules       = var.allowed_ip_rules
  }

  tags = var.tags
}

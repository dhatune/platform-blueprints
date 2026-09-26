# Destination for diagnostic settings.
#
# Activity Log and platform metrics are always on in Azure, at no cost and
# with no configuration; what does NOT happen without a diagnostic setting is
# the resource-level log a service emits about its own operation -- a
# firewall's per-rule match, a vault's audit trail, a cluster's audit log --
# and that has to be named per resource. This workspace is that destination:
# permanent, because an idle workspace costs almost nothing and the platform layer it
# lives in is meant to stay up; the diagnostic settings that point resources
# at it belong to whichever layer creates the resource, and are ephemeral
# when that resource is.

resource "azurerm_log_analytics_workspace" "this" {
  name                = "log-${var.name_prefix}"
  location            = var.location
  resource_group_name = var.resource_group_name

  # PerGB2018 is the pay-as-you-go SKU and the one this lab wants: cost here
  # tracks retention, not ingestion volume, and volume is what the Capacity
  # Reservation commitment tiers Azure still sells are priced against. Only
  # the legacy per-node tier is closed to new workspaces.
  sku = "PerGB2018"

  retention_in_days = var.retention_in_days

  tags = var.tags
}

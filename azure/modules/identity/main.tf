# Workload identity.
#
# The federated credential lets a Kubernetes service account exchange its own
# token for an Azure token. Nothing is stored: no client secret, no certificate,
# no key in a manifest. This is what makes "no static credentials" true rather
# than aspirational.

resource "azurerm_user_assigned_identity" "this" {
  name                = "id-${var.name_prefix}-${var.purpose}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

locals {
  # Declared only once the cluster has published an issuer.
  federation_ready = var.oidc_issuer_url != "" && var.service_account_name != "" && var.service_account_namespace != ""
}

resource "azurerm_federated_identity_credential" "this" {
  for_each = local.federation_ready ? { default = true } : {}

  name = "fic-${var.name_prefix}-${var.purpose}"

  # user_assigned_identity_id already encodes the resource group; both
  # resource_group_name and parent_id are deprecated here.
  user_assigned_identity_id = azurerm_user_assigned_identity.this.id
  issuer                    = var.oidc_issuer_url
  subject                   = "system:serviceaccount:${var.service_account_namespace}:${var.service_account_name}"

  # Fixed by Azure. Any other value fails the exchange without a useful error.
  audience = ["api://AzureADTokenExchange"]
}

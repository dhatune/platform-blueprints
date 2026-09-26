# Permanent platform layer of the laboratory profile.
#
# Everything declared here is cheap to keep (about fifteen dollars a month,
# mostly two private endpoints) and stays up between working sessions.
# The parts that cost money live in 20-workload and are destroyed when a session
# ends. That split is what makes the teardown discipline sustainable: coming
# back is one apply of one stack, not a rebuild of the whole estate.

module "naming" {
  source = "../../../modules/naming"

  prefix         = var.prefix
  workload       = var.workload
  environment    = "lab"
  location_short = var.location_short
  instance       = "01"
}

module "hub" {
  source = "../../../modules/network-hub"

  name_prefix   = module.naming.base
  location      = var.location
  address_space = var.hub_address_space
  tags          = module.naming.tags
}

# Reachable from the cluster subnet on 443, so a rule can name this group as
# its destination instead of the whole endpoints subnet -- letting the
# cluster reach the vault and the registry privately while the object
# repository's endpoint, which never joins this group, stays behind the
# default deny.
#
# Created in the hub's resource group, not the spoke's, and that placement is
# deliberate rather than an oversight: this group's id is consumed by
# local.allow_rules below, which becomes an input to module "spoke" itself.
# A resource scoped to module.spoke.resource_group_name would depend on that
# module's own output while also feeding one of that same module's inputs --
# a dependency cycle Terraform refuses to plan. Nothing about an application
# security group requires it to live in the same resource group as the
# subnet or the endpoints that join it; only the graph does.
resource "azurerm_application_security_group" "cluster_reachable" {
  name                = "asg-${module.naming.base}-cluster-reachable"
  location            = var.location
  resource_group_name = module.hub.resource_group_name
  tags                = module.naming.tags
}

locals {
  # var.allow_rules cannot carry this entry itself: a variable default is
  # static and cannot reference azurerm_application_security_group.cluster_reachable,
  # which does not exist until this stack applies. Merged in here instead,
  # on top of whatever the variable already declares.
  allow_rules = merge(var.allow_rules, {
    cluster_to_reachable_endpoints_https = {
      subnet_key                                 = "endpoints"
      priority                                   = 200
      direction                                  = "Inbound"
      protocol                                   = "Tcp"
      source_address_prefix                      = var.subnets["cluster"].address_prefix
      destination_application_security_group_ids = [azurerm_application_security_group.cluster_reachable.id]
      destination_port_range                     = "443"
      description                                = "Cluster reaches endpoints joined to the reachable group; the repository's endpoint is not joined and stays behind the default deny."
    }

    # Pod to pod across nodes. Under CNI Overlay these packets carry pod
    # addresses, which are not part of the virtual network, so neither the
    # deny at 4000 nor Azure's AllowVnetInBound matches them and the default
    # DenyAllInBound drops them. A one-node cluster never shows it; the second
    # node's pods cannot reach DNS or anything else on the first.
    pod_to_pod = {
      subnet_key                 = "cluster"
      priority                   = 220
      direction                  = "Inbound"
      protocol                   = "*"
      source_address_prefix      = var.pod_cidr
      destination_address_prefix = var.pod_cidr
      destination_port_range     = "*"
      description                = "Pod to pod traffic between nodes under CNI Overlay carries pod addresses outside the virtual network."
    }

    # Node to pod, the other half of Microsoft's guidance for CNI Overlay
    # behind an NSG: a node reaching a pod on another node addresses the pod
    # directly, and that destination is outside the virtual network too.
    node_to_pod = {
      subnet_key                 = "cluster"
      priority                   = 221
      direction                  = "Inbound"
      protocol                   = "*"
      source_address_prefix      = var.subnets["cluster"].address_prefix
      destination_address_prefix = var.pod_cidr
      destination_port_range     = "*"
      description                = "Nodes reaching pods on other nodes under CNI Overlay address pod IPs outside the virtual network."
    }
  })
}

module "spoke" {
  source = "../../../modules/network-spoke"

  name_prefix   = module.naming.base
  location      = var.location
  address_space = var.spoke_address_space
  subnets       = var.subnets
  allow_rules   = local.allow_rules

  hub_vnet_id             = module.hub.vnet_id
  hub_vnet_name           = module.hub.vnet_name
  hub_resource_group_name = module.hub.resource_group_name
  firewall_private_ip     = var.firewall_private_ip

  tags = module.naming.tags
}

module "private_dns" {
  source = "../../../modules/private-dns"

  name_prefix         = module.naming.base
  resource_group_name = module.hub.resource_group_name
  zone_names          = var.private_dns_zone_names

  vnet_ids = {
    hub   = module.hub.vnet_id
    spoke = module.spoke.vnet_id
  }

  tags = module.naming.tags
}

module "workload_identity" {
  source = "../../../modules/identity"

  name_prefix         = module.naming.base
  purpose             = "workload"
  resource_group_name = module.spoke.resource_group_name
  location            = var.location
  tags                = module.naming.tags

  # The federated credential is completed in 20-workload, once the cluster has
  # published its issuer.
}

module "keyvault" {
  source = "../../../modules/keyvault"

  name_prefix         = module.naming.storage_base
  resource_group_name = module.spoke.resource_group_name
  location            = var.location
  tenant_id           = var.tenant_id
  tags                = module.naming.tags

  # The operator's machine is where Terraform runs and where the one secret
  # this stack writes gets written from. See the variable's own comment for
  # why this is a declared exception rather than a relaxed default.
  public_network_access_enabled = length(var.vault_operator_ip_rules) > 0
  allowed_ip_rules              = var.vault_operator_ip_rules
}

# The workload stack writes a secret to this vault from the operator's
# machine. The vault authorises by Azure RBAC, and Owner on the subscription
# does not include the data plane, so the identity running Terraform gets the
# one role that write needs, scoped to this vault only.
data "azurerm_client_config" "current" {}

resource "azurerm_role_assignment" "deployer_vault_secrets" {
  scope                = module.keyvault.key_vault_id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

module "storage" {
  source = "../../../modules/storage"

  storage_base        = module.naming.storage_base
  resource_group_name = module.spoke.resource_group_name
  location            = var.location
  replication_type    = var.storage_replication_type
  tags                = module.naming.tags
}

module "keyvault_endpoint" {
  source = "../../../modules/private-endpoint"

  name_prefix         = module.naming.base
  service_key         = "keyvault"
  location            = var.location
  resource_group_name = module.spoke.resource_group_name
  subnet_id           = module.spoke.subnet_ids["endpoints"]
  target_resource_id  = module.keyvault.key_vault_id
  subresource_name    = "vault"
  private_dns_zone_id = module.private_dns.zone_ids["privatelink.vaultcore.azure.net"]

  # The cluster reaches this endpoint through local.allow_rules above, which
  # targets this same group as its destination.
  application_security_group_ids = [azurerm_application_security_group.cluster_reachable.id]

  tags = module.naming.tags
}

# Nothing in the vault's own resource logs the reads and writes on its data
# plane until a diagnostic setting says so; AuditEvent is the category that
# carries them.
resource "azurerm_monitor_diagnostic_setting" "keyvault" {
  name                       = "diag-${module.naming.base}-keyvault"
  target_resource_id         = module.keyvault.key_vault_id
  log_analytics_workspace_id = module.observability.workspace_id

  enabled_log {
    category = "AuditEvent"
  }
}

module "storage_endpoint" {
  source = "../../../modules/private-endpoint"

  name_prefix         = module.naming.base
  service_key         = "storage"
  location            = var.location
  resource_group_name = module.spoke.resource_group_name
  subnet_id           = module.spoke.subnet_ids["endpoints"]
  target_resource_id  = module.storage.storage_account_id
  subresource_name    = "blob"
  private_dns_zone_id = module.private_dns.zone_ids["privatelink.blob.core.windows.net"]

  tags = module.naming.tags
}

module "policy" {
  source = "../../../modules/policy"

  name_prefix       = module.naming.base
  subscription_id   = var.subscription_id
  allowed_locations = [var.location]
}

module "observability" {
  source = "../../../modules/observability"

  name_prefix         = module.naming.base
  location            = var.location
  resource_group_name = module.spoke.resource_group_name
  tags                = module.naming.tags
}

# Azure provisions one regional Network Watcher per subscription automatically
# the first time networking is used in a region, in a resource group named
# NetworkWatcherRG that this landing zone did not create and does not own.
# Referenced by data source rather than declared as a resource: creating it
# here would either collide with the one Azure already made or, if this
# stack's own copy were ever destroyed, take flow logging down with it for
# every other network in the subscription that also depends on it.
data "azurerm_network_watcher" "this" {
  name                = "NetworkWatcher_${var.location}"
  resource_group_name = "NetworkWatcherRG"
}

# A storage account of its own, not the object repository: flow logs are
# written by the Network Watcher service, not by this landing zone's own
# workload, and mixing the two would put a platform log stream and
# application data in the same account and the same blast radius.
resource "azurerm_storage_account" "flow_logs" {
  name                = substr("stfl${module.naming.storage_base}", 0, 24)
  resource_group_name = module.hub.resource_group_name
  location            = var.location

  account_tier             = "Standard"
  account_kind             = "StorageV2"
  account_replication_type = "LRS"

  # Shared keys stay enabled here, unlike modules/storage. The flow log
  # resource authenticates to this account itself, as the Network Watcher
  # platform service, not as anything this landing zone's own Entra identities
  # control -- the provider's schema for azurerm_network_watcher_flow_log
  # carries no identity block through which a managed identity could be
  # offered instead, so there is no Entra-only path this module could take.
  shared_access_key_enabled = true

  https_traffic_only_enabled      = true
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false

  tags = module.naming.tags
}

# VNet flow logs on the spoke, not NSG flow logs: target_resource_id names
# the virtual network itself, which captures every subnet's traffic in one
# declaration rather than one flow log per security group.
resource "azurerm_network_watcher_flow_log" "spoke" {
  name                 = "fl-${module.naming.base}-spoke"
  network_watcher_name = data.azurerm_network_watcher.this.name
  resource_group_name  = data.azurerm_network_watcher.this.resource_group_name

  target_resource_id = module.spoke.vnet_id
  storage_account_id = azurerm_storage_account.flow_logs.id
  enabled            = true

  retention_policy {
    enabled = true
    days    = 7
  }

  # Traffic analytics is deliberately off. It bills by ingested volume on top
  # of the flow log itself, and this lab's own logging spend should track
  # what check 6 and check 8 actually need to read, not a second product
  # layered on top of it. The block is omitted entirely rather than declared
  # with enabled = false: the schema requires workspace_id, workspace_region
  # and workspace_resource_id together whenever the block is present at all,
  # even to say no.
}

# Notifications at 50% and 90% of actual spend, and at 100% of the forecast --
# catching a runaway before the invoice, not only after it. Nothing is
# created while var.budget_contact_emails is empty: a budget alert nobody
# receives is not a control, and an example address baked into this module
# would only ever notify whoever happened to copy it.
resource "azurerm_consumption_budget_subscription" "this" {
  count = length(var.budget_contact_emails) > 0 ? 1 : 0

  name            = "budget-${module.naming.base}"
  subscription_id = "/subscriptions/${var.subscription_id}"
  amount          = var.budget_amount
  time_grain      = "Monthly"

  # Azure accepts a start date only within the current billing month, so it is
  # the first day of the month the budget is created in, and later plans leave
  # it alone rather than moving it every month.
  time_period {
    start_date = formatdate("YYYY-MM-01'T'00:00:00Z", timestamp())
  }

  lifecycle {
    ignore_changes = [time_period]
  }

  notification {
    enabled        = true
    threshold      = 50
    threshold_type = "Actual"
    operator       = "GreaterThan"
    contact_emails = var.budget_contact_emails
  }

  notification {
    enabled        = true
    threshold      = 90
    threshold_type = "Actual"
    operator       = "GreaterThan"
    contact_emails = var.budget_contact_emails
  }

  notification {
    enabled        = true
    threshold      = 100
    threshold_type = "Forecasted"
    operator       = "GreaterThan"
    contact_emails = var.budget_contact_emails
  }
}

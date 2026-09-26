# The ephemeral half of the lab. Everything here bills by the hour and is
# destroyed at the end of a session; the permanent layer underneath it stays
# up between sessions.
#
# Read live/lab/10-platform first: this stack consumes its outputs and adds
# nothing to the network.

data "terraform_remote_state" "platform" {
  backend = "azurerm"

  config = {
    resource_group_name  = var.platform_state_resource_group_name
    storage_account_name = var.platform_state_storage_account_name
    container_name       = var.platform_state_container_name
    key                  = var.platform_state_key
    use_azuread_auth     = true
  }
}

module "naming" {
  source = "../../../modules/naming"

  # Same inputs as the platform stack, so both layers derive the same names.
  # A mismatch here produces a second set of resources beside the first rather
  # than an error.
  prefix         = var.prefix
  workload       = var.workload
  environment    = "lab"
  location_short = var.location_short
  instance       = "01"
}

locals {
  platform = data.terraform_remote_state.platform.outputs
}

module "firewall" {
  source = "../../../modules/firewall"

  name_prefix          = module.naming.base
  location             = local.platform.location
  resource_group_name  = local.platform.hub_resource_group_name
  subnet_id            = local.platform.firewall_subnet_id
  management_subnet_id = local.platform.firewall_management_subnet_id
  # Read, not restated: the permanent layer publishes the address its own
  # default route points at, so this stack reads that published value instead
  # of naming its own literal that could drift from it.
  expected_private_ip = local.platform.spoke_default_route_next_hop
  tags                = module.naming.tags

  # Every egress rule is sourced from the spoke's own address space, not
  # from "*".
  allowed_source_addresses = local.platform.spoke_address_space

  # No network rules. A private cluster reaches its control plane through a
  # private endpoint, and its outbound dependencies travel as the FQDN tag
  # below. The regional AzureCloud service tag is deliberately absent: it
  # covers every public address Azure hosts in the region, other tenants'
  # included, which makes it an exfiltration path rather than a dependency.
  allowed_service_tags = {}

  # Microsoft maintains the contents. Writing the list by hand is how a cluster
  # stops provisioning three months later when an endpoint moves.
  allowed_fqdn_tags = ["AzureKubernetesService"]

  # Hosts this landing zone chose, as opposed to the list above that Microsoft
  # maintains. Empty until something names one.
  allowed_fqdns = var.allowed_egress_fqdns

  # The one way in. Layer 4 only: this forwards packets to the ingress
  # controller's internal load balancer and nothing more -- no TLS
  # termination, no routing by host or path. That work belongs to the ingress
  # controller behind it.
  inbound_nat_rules = {
    ingress_http = {
      protocols          = ["TCP"]
      source_addresses   = var.ingress_source_addresses
      destination_port   = "80"
      translated_address = var.ingress_internal_address
      translated_port    = 80
    }

    # Declared before anything terminates TLS, deliberately. The certificate
    # comes later and the path has to exist first: an automated certificate
    # issued over the HTTP challenge is requested on 80 and then served on
    # 443, so a path that opens only 80 gets a certificate nobody can use.
    ingress_https = {
      protocols          = ["TCP"]
      source_addresses   = var.ingress_source_addresses
      destination_port   = "443"
      translated_address = var.ingress_internal_address
      translated_port    = 443
    }
  }
}

# Activity Log and platform metrics are always on in Azure at no cost; what a
# diagnostic setting adds is the resource-level log a service emits about its
# own operation, per resource -- and without one here, the day someone needs
# to see why a flow was allowed or denied, there is nothing to look at.
# Ephemeral like the firewall it watches: torn down and recreated with every
# session, pointed at the permanent workspace the platform layer keeps up
# between them.
#
# AZFWNetworkRule and AZFWApplicationRule are the structured, per-match logs
# for the two rule kinds this firewall actually evaluates -- network rules
# (service tags) and application rules (FQDN tags, see docs/decisions/0010).
# Confirmed against Microsoft's own reference for Microsoft.Network/azureFirewalls
# resource logs; the legacy AzureFirewallNetworkRule/AzureFirewallApplicationRule
# names route through the catch-all AzureDiagnostics table and are not used
# here. A category name the provider does not validate against a live list is
# accepted and silently sends nothing -- the same shape of failure as a
# mistyped policy alias or an FQDN a Basic-tier network rule cannot match.
#
# log_analytics_destination_type = "Dedicated" sends each category to its own
# resource-specific table -- AZFWNetworkRule and AZFWApplicationRule, named
# after the category itself -- rather than into the shared AzureDiagnostics
# catch-all every category lands in by default. A resource-specific table
# carries typed columns (Action, Fqdn, and so on) that AzureDiagnostics only
# ever stores as a single opaque JSON blob column, which is what
# scripts/verify/06-egress-leaves-by-the-defined-route.sh queries against.
resource "azurerm_monitor_diagnostic_setting" "firewall" {
  name                       = "diag-${module.naming.base}-firewall"
  target_resource_id         = module.firewall.firewall_id
  log_analytics_workspace_id = local.platform.log_analytics_workspace_id

  log_analytics_destination_type = "Dedicated"

  enabled_log {
    category = "AZFWNetworkRule"
  }

  enabled_log {
    category = "AZFWApplicationRule"
  }
}

module "acr" {
  source = "../../../modules/acr"

  name_prefix         = module.naming.base
  registry_base       = module.naming.storage_base
  location            = local.platform.location
  resource_group_name = local.platform.spoke_resource_group_name
  tags                = module.naming.tags
}

module "acr_endpoint" {
  source = "../../../modules/private-endpoint"

  name_prefix         = module.naming.base
  service_key         = "registry"
  location            = local.platform.location
  resource_group_name = local.platform.spoke_resource_group_name
  subnet_id           = local.platform.subnet_ids["endpoints"]
  target_resource_id  = module.acr.registry_id
  subresource_name    = "registry"
  private_dns_zone_id = local.platform.private_dns_zone_ids["privatelink.azurecr.io"]

  # Joins the same group the vault's endpoint joined in the platform layer,
  # so the cluster's allow rule -- which targets this group, not the whole
  # endpoints subnet -- reaches the registry too.
  application_security_group_ids = [local.platform.application_security_group_id]

  tags = module.naming.tags
}

# The secret below is a generic value with
# no privileged meaning of its own, written to the vault so check 4 has
# something to prove: that a pod holding the workload identity can read a
# secret from the vault by identity, with no credential of its own baked in.
# The federated credential and role assignment further down are what make
# that read possible; this secret is only the payload the check fetches.
resource "random_password" "probe" {
  length      = 32
  special     = true
  min_upper   = 1
  min_lower   = 1
  min_numeric = 1
  min_special = 1
}

resource "azurerm_key_vault_secret" "probe" {
  name         = "workload-probe-secret"
  value        = random_password.probe.result
  key_vault_id = local.platform.key_vault_id
}

module "aks" {
  source = "../../../modules/aks"

  name_prefix         = module.naming.base
  location            = local.platform.location
  resource_group_name = local.platform.spoke_resource_group_name
  subnet_id           = local.platform.subnet_ids["cluster"]

  node_vm_size = var.node_vm_size
  node_count   = var.node_count

  pod_cidr       = local.platform.pod_cidr
  service_cidr   = var.service_cidr
  dns_service_ip = var.dns_service_ip

  acr_id         = module.acr.registry_id
  route_table_id = local.platform.spoke_route_table_id

  # Entra integration is what lets local_account_disabled be true (see the
  # module's own comment). admin_group_object_ids is left at its default
  # empty list: this lab profile grants cluster administration through
  # separate Azure role assignments, not through a group holding the
  # built-in admin claim.
  tenant_id = var.tenant_id

  tags = module.naming.tags

  # With userDefinedRouting, AKS reads the subnet's route table
  # during creation and refuses a subnet whose default route is missing or
  # points straight at the internet. And a cluster that comes up before the
  # firewall has its rules cannot reach its own control plane, so it fails
  # partway through a ten minute provision with an error that names none of
  # this.
  depends_on = [
    module.firewall,
  ]
}

# The identity is created in the permanent layer, but the credential must
# trust the cluster's OIDC issuer, and that URL does not exist until the
# cluster does. So the identity lives in 10-platform and its trust is
# established here, once module.aks has something to trust: a separate
# resource, in another layer, created at another time.
resource "azurerm_federated_identity_credential" "workload" {
  name = "fic-${module.naming.base}-workload"

  # user_assigned_identity_id, not the deprecated parent_id, which azurerm
  # v5.0 removes.
  user_assigned_identity_id = local.platform.workload_identity_id
  issuer                    = module.aks.oidc_issuer_url
  subject                   = "system:serviceaccount:${var.workload_service_account_namespace}:${var.workload_service_account_name}"

  # Fixed by Azure. Any other value fails the exchange without a useful error.
  audience = ["api://AzureADTokenExchange"]
}

# The narrowest grant that lets the workload identity read the secret this
# stack wrote above: scoped to the vault itself, not the resource group it
# lives in.
resource "azurerm_role_assignment" "workload_identity_vault_secrets_user" {
  scope                = local.platform.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = local.platform.workload_identity_principal_id
}

# Check 8 asks whether an unauthorised flow is denied. It needs a second
# vantage point, not a second machine: both halves run from a pod in
# snet-cluster, the denied direction toward the object repository's private
# endpoint (which never joined the reachable group) and the permitted
# direction toward the vault and registry endpoints (which did). That tests
# the same rule pair a dedicated VM would, without a machine competing for
# the subscription's four-vCPU quota.

# The cluster authorises Kubernetes calls through Azure RBAC and has no local
# accounts, so whoever runs Terraform and the verification scripts needs a
# role on the cluster itself. Owner on the subscription does not carry the
# Kubernetes data actions. Without this every `az aks command invoke` comes
# back Forbidden. Role assignments take a few minutes to propagate.
data "azurerm_client_config" "current" {}

resource "azurerm_role_assignment" "deployer_cluster_admin" {
  scope                = module.aks.cluster_id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Without this, nothing records who called the Kubernetes API or what they
# did once local accounts are gone and Azure RBAC is the only door in --
# kube-audit-admin is the category that carries writes and non-get reads,
# which is what an audit trail is actually for.
resource "azurerm_monitor_diagnostic_setting" "aks" {
  name                       = "diag-${module.naming.base}-aks"
  target_resource_id         = module.aks.cluster_id
  log_analytics_workspace_id = local.platform.log_analytics_workspace_id

  enabled_log {
    category = "kube-audit-admin"
  }
}

# Check 5 (scripts/verify/05-pod-pulls-from-the-registry.sh) needs the
# workload identity itself to hold this, not only the kubelet identity
# modules/aks already grants AcrPull to: a pod authenticating as the
# workload identity through workload identity federation, rather than as the
# node's own kubelet, has no path to the registry without its own grant.
# Push, not pull, because this is the identity a build or deployment
# pipeline assumes to publish an image, not the one a running pod pulls one
# with.
resource "azurerm_role_assignment" "workload_identity_acr_push" {
  scope                = module.acr.registry_id
  role_definition_name = "AcrPush"
  principal_id         = local.platform.workload_identity_principal_id
}

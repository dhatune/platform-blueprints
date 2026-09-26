# Private Kubernetes cluster with no egress of its own.
#
# Four settings here are load bearing and each fails in a different way if it
# is wrong:
#
#   private_cluster_enabled  the API server gets no public address. Check 3.
#   outbound_type            userDefinedRouting means AKS provisions NO
#                            outbound load balancer and no egress address. All
#                            traffic must leave through the route already on
#                            the subnet. AKS validates that route at creation:
#                            if it is missing, or points straight at the
#                            internet, creation is refused.
#   network_plugin_mode      overlay takes pod addresses out of the virtual
#                            network. Without it every pod consumes a subnet
#                            address and a /24 node subnet caps the cluster.
#   workload_identity        with the OIDC issuer, this is what lets a pod
#                            reach the vault with no secret in its manifest.
#
# The node pool is a single regular node, sized Standard_D2als_v7. Spot is not
# used: the system pool cannot run on spot, and the trial offer this lab runs
# on cannot use spot at all (docs/decisions/0011).
#
# The control plane's own identity is created below, before the cluster,
# rather than left to the system-assigned identity AKS would otherwise
# provision. A system-assigned identity's principal id does not exist until
# the cluster itself is created, so anything granting that identity a role
# has to be declared after the cluster and the cluster has to depend on
# nothing in return -- which is exactly backwards for userDefinedRouting,
# where the cluster needs those roles in place before it can validate the
# subnet's route table at creation. A user-assigned identity exists first,
# can be granted its roles first, and the cluster then depends on those
# grants rather than the other way around.
resource "azurerm_user_assigned_identity" "control_plane" {
  name                = "id-${var.name_prefix}-aks-control-plane"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

# Granted before the cluster exists, and scoped to exactly the two objects
# the control plane needs to read for userDefinedRouting: the subnet itself
# and the route table carrying its default route. Not the resource group
# either lives in -- an identity that manages this cluster's network path has
# no business reading or touching anything else the resource group holds.
resource "azurerm_role_assignment" "network_subnet" {
  scope                = var.subnet_id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.control_plane.principal_id
}

resource "azurerm_role_assignment" "network_route_table" {
  scope                = var.route_table_id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.control_plane.principal_id
}

resource "azurerm_kubernetes_cluster" "this" {
  name                = "aks-${var.name_prefix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  dns_prefix = replace("aks-${var.name_prefix}", "/[^a-zA-Z0-9-]/", "")

  # Free. The Standard tier buys a financially backed uptime guarantee, which
  # is meaningless for a cluster that is destroyed at the end of every session.
  sku_tier = "Free"

  # Null lets Azure choose its own current default rather than this module
  # naming a version that is only ever accurate on the day it is written.
  kubernetes_version = var.kubernetes_version

  # The API server has no public address at all.
  private_cluster_enabled = true

  # Local Kubernetes accounts are a static credential by another name.
  local_account_disabled            = true
  role_based_access_control_enabled = true

  # local_account_disabled and this block are a pair, not two independent
  # choices. Since Kubernetes 1.25, Azure refuses disableLocalAccounts on a
  # cluster that is not Entra integrated -- creation fails with an explicit
  # message to that effect. So this block exists for the same reason the
  # setting above does: local_account_disabled removes the static credential,
  # and Entra integration is what Azure requires before it will let you
  # remove it. A reader who sees only one of the two will not understand why
  # either is there.
  #
  # azure_rbac_enabled routes cluster authorisation through Azure role
  # assignments rather than through Kubernetes RoleBindings managed
  # separately -- the same posture this blueprint already takes everywhere
  # else: identity and access live in Azure, not in a cluster-local object
  # nobody audits. admin_group_object_ids is left to the caller (see
  # variables.tf): an empty list is valid and means administration is
  # granted by Azure role assignment alone.
  azure_active_directory_role_based_access_control {
    azure_rbac_enabled     = true
    admin_group_object_ids = var.admin_group_object_ids
    tenant_id              = var.tenant_id
  }

  # The two halves of workload identity. The issuer publishes the token
  # signing keys; the flag makes the cluster project those tokens into pods.
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  # No Azure Policy add-on. The add-on installs Gatekeeper and a sync of
  # policy assignments into the cluster, but ships no assignment of its own --
  # it denies nothing until a policy assignment targets this cluster, and
  # none is declared here. Turning it on would add a running Gatekeeper
  # deployment with nothing to enforce.
  azure_policy_enabled = false

  default_node_pool {
    name           = "system"
    vm_size        = var.node_vm_size
    node_count     = var.node_count
    vnet_subnet_id = var.subnet_id

    # Nodes with public addresses would defeat the whole topology. This
    # setting is what prevents them: the subscription policy on network
    # interfaces does not inspect scale-set NICs. Check 3 verifies the result.
    node_public_ip_enabled = false

    # Azure fills this in on create when it is left out, and every plan after
    # the first then proposes removing it. Declaring the value Azure chooses
    # keeps a fresh deployment at zero drift.
    upgrade_settings {
      max_surge = "10%"
    }
  }

  # User-assigned rather than the system-assigned identity AKS would
  # otherwise provision. See the identity's own comment above the two role
  # assignments this depends on: those grants exist before the cluster does,
  # which the depends_on below makes explicit.
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.control_plane.id]
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    outbound_type       = "userDefinedRouting"
    load_balancer_sku   = "standard"

    # Cilium's eBPF dataplane. Declaring network_policy without also setting
    # network_data_plane to the matching value is rejected by the provider;
    # neither one denies a single packet on its own until a Kubernetes
    # NetworkPolicy object actually exists in the cluster. This only makes
    # such an object possible to enforce, later.
    network_policy     = "cilium"
    network_data_plane = "cilium"

    pod_cidr       = var.pod_cidr
    service_cidr   = var.service_cidr
    dns_service_ip = var.dns_service_ip
  }

  # Azure ships a security patch every month and a new minor version several
  # times a year; a cluster nobody revisits drifts out of support silently.
  # "patch" takes the automated part only as far as patches within the minor
  # version already running -- a minor upgrade still needs a deliberate
  # change to this module's kubernetes_version. "NodeImage" refreshes node
  # OS images on the same cadence, independently of the Kubernetes version
  # itself.
  automatic_upgrade_channel = "patch"
  node_os_upgrade_channel   = "NodeImage"

  # Both channels default to whatever moment an upgrade happens to become
  # available, which for a lab cluster serving nothing in particular is early
  # Sunday UTC -- outside any hours the ingress path in live/lab/20-workload
  # is likely to be under active use.
  maintenance_window_auto_upgrade {
    frequency   = "Weekly"
    interval    = 1
    duration    = 4
    day_of_week = "Sunday"
    start_time  = "01:00"
    utc_offset  = "+00:00"
  }

  maintenance_window_node_os {
    frequency   = "Weekly"
    interval    = 1
    duration    = 4
    day_of_week = "Sunday"
    start_time  = "01:00"
    utc_offset  = "+00:00"
  }

  # The two network role assignments are created before this resource, not
  # after: with userDefinedRouting, AKS validates the subnet's route table at
  # creation, and a control plane identity that cannot yet read it fails
  # partway through a ten-minute provision with an error naming neither the
  # missing role nor its scope.
  depends_on = [
    azurerm_role_assignment.network_subnet,
    azurerm_role_assignment.network_route_table,
  ]
}

# Check 5: a pod pulls an image with no pull secret in its manifest. That works
# only if the kubelet's own identity may read the registry.
#
# kubelet_identity is a computed BLOCK, and this module declares no such block.
# Azure's provider returns that block unknown while planning and populated after
# the apply, so the index below always resolves and the fallback is never
# exercised against Azure. A mocked provider returns the same block as a known
# empty list instead -- indexing it is a hard plan error, and without the
# fallback this module could not be planned by terraform test at all. The
# fallback is the nil GUID because no principal carries it: Azure refuses a role
# assignment to it with a clear error rather than granting anything, and a
# reader recognises on sight that it is not an identity.
# Upstream: hashicorp/terraform-provider-azurerm#25691.
resource "azurerm_role_assignment" "acr_pull" {
  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = try(azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id, "00000000-0000-0000-0000-000000000000")
}

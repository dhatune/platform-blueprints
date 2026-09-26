mock_provider "azurerm" {
  mock_resource "azurerm_kubernetes_cluster" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.ContainerService/managedClusters/aks"
    }
  }

  # Gives the control plane's identity a known principal id under plan, so a
  # pairing assertion between the two role assignments and the identity they
  # were granted to can be written without requiring apply.
  mock_resource "azurerm_user_assigned_identity" {
    defaults = {
      id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ops-alz-lab-eus2-01-spoke/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-ops-alz-lab-eus2-01-aks-control-plane"
      principal_id = "44444444-4444-4444-4444-444444444444"
    }
  }
}

# kubelet_identity cannot be mocked. It is a nested BLOCK, not a computed
# attribute, and this module declares no such block, so Terraform plans it as a
# known EMPTY list rather than as unknown the way the real provider does. Mock
# values only fill instances that already exist, so defaults (list form and
# object form), override_resource at file and run scope, and override_during =
# plan all leave it empty -- verified on Terraform 1.10.3 and 1.16.2. That is
# why both reads of kubelet_identity[0] fall back to the nil GUID: under a
# mocked plan the fallback is what lets the module be planned at all, and
# against Azure the value is unknown at plan, so try passes it through and the
# fallback never appears. Upstream: hashicorp/terraform-provider-azurerm#25691.

variables {
  name_prefix         = "ops-alz-lab-eus2-01"
  location            = "eastus2"
  resource_group_name = "rg-ops-alz-lab-eus2-01-spoke"
  subnet_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-cluster"
  node_vm_size        = "Standard_B2als_v2"
  node_count          = 1
  pod_cidr            = "192.168.0.0/16"
  service_cidr        = "172.16.0.0/16"
  dns_service_ip      = "172.16.0.10"
  acr_id              = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.ContainerRegistry/registries/acr"
  route_table_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ops-alz-lab-eus2-01-spoke/providers/Microsoft.Network/routeTables/rt-ops-alz-lab-eus2-01-spoke"
  # Fixture tenant, not a real one -- this file is committed.
  tenant_id = "00000000-0000-0000-0000-000000000000"
  tags      = { environment = "lab" }
}

run "nothing_about_the_cluster_is_reachable_from_the_internet" {
  command = plan

  # Check 3 of the definition of done, in two halves. Either one left on makes
  # the other pointless.
  assert {
    condition     = azurerm_kubernetes_cluster.this.private_cluster_enabled == true
    error_message = "the api server must have no public address"
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.default_node_pool[0].node_public_ip_enabled == false
    error_message = "a node with a public address bypasses the entire egress path"
  }
}

run "the_cluster_provisions_no_egress_of_its_own" {
  command = plan

  # With any other outbound type AKS creates a load balancer with a public
  # address and the workload leaves through it -- never touching the firewall,
  # while every route in the topology still looks correct.
  assert {
    condition     = azurerm_kubernetes_cluster.this.network_profile[0].outbound_type == "userDefinedRouting"
    error_message = "any other outbound type gives the cluster its own egress address and the firewall stops being the only way out"
  }
}

run "pod_addresses_do_not_come_out_of_the_subnet" {
  command = plan

  assert {
    condition     = azurerm_kubernetes_cluster.this.network_profile[0].network_plugin_mode == "overlay"
    error_message = "without overlay every pod consumes a subnet address and a /24 caps the cluster at a few hundred pods"
  }
}

run "the_default_ranges_are_accepted" {
  command = plan

  # The positive half. A guard that refuses everything would pass both negative
  # runs below and make the module unusable.
  assert {
    condition     = azurerm_kubernetes_cluster.this.network_profile[0].dns_service_ip == var.dns_service_ip
    error_message = "the defaults this lab ships with must pass their own guards"
  }

  # Each range must reach the attribute that carries it. Swapping the two in the
  # network profile plans clean and produces a cluster whose services and pods
  # draw from each other's range.
  assert {
    condition     = azurerm_kubernetes_cluster.this.network_profile[0].pod_cidr == var.pod_cidr
    error_message = "the pod range must reach pod_cidr, not the service range"
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.network_profile[0].service_cidr == var.service_cidr
    error_message = "the service range must reach service_cidr, not the pod range"
  }
}

run "ranges_that_overlap_are_refused_by_the_configuration" {
  command = plan

  # Two different strings describing overlapping addresses -- the case a
  # string comparison misses entirely.
  variables {
    pod_cidr     = "172.16.0.0/16"
    service_cidr = "172.16.128.0/17"

    # Moved inside the mutated service range on purpose. Left at the fixture
    # default it would be outside it, making the run carry a second invalid
    # input that only stays quiet because Terraform skips a validation whose
    # referenced variable already failed.
    dns_service_ip = "172.16.128.10"
  }

  expect_failures = [var.service_cidr]
}

run "a_dns_address_outside_its_own_service_range_is_refused" {
  command = plan

  # Shares a first octet with the service range and is still outside it, which
  # is what a prefix comparison would wave through.
  variables {
    service_cidr   = "172.16.0.0/16"
    dns_service_ip = "172.17.0.10"
  }

  expect_failures = [var.dns_service_ip]
}

run "a_pod_can_hold_an_identity_without_holding_a_secret" {
  command = plan

  # Both halves are required. The issuer alone publishes keys nobody uses; the
  # flag alone projects tokens no federation trusts.
  assert {
    condition     = azurerm_kubernetes_cluster.this.oidc_issuer_enabled == true
    error_message = "workload identity needs the issuer to publish its signing keys"
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.workload_identity_enabled == true
    error_message = "without this the cluster never projects a token into the pod"
  }
}

run "there_is_no_local_administrator_to_steal" {
  command = plan

  assert {
    condition     = azurerm_kubernetes_cluster.this.local_account_disabled == true
    error_message = "a local kubernetes account is a static credential by another name"
  }
}

run "local_accounts_are_disabled_only_because_entra_replaces_them" {
  command = plan

  # The pair is the point. Since Kubernetes 1.25, Azure refuses
  # disableLocalAccounts on a cluster that is not AAD integrated, so
  # asserting either half without the other would pass a plan that fails at
  # apply against the real API.
  assert {
    condition     = azurerm_kubernetes_cluster.this.local_account_disabled == true
    error_message = "local accounts must stay disabled -- removing the static credential is the whole point of the pair"
  }

  assert {
    condition     = length(azurerm_kubernetes_cluster.this.azure_active_directory_role_based_access_control) == 1
    error_message = "without this block present, Azure refuses to create a cluster with local accounts disabled"
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.azure_active_directory_role_based_access_control[0].azure_rbac_enabled == true
    error_message = "cluster authorisation must be decided by Azure role assignments, not by Kubernetes RoleBindings managed separately"
  }
}

run "the_entra_block_carries_the_tenant_the_caller_supplied" {
  command = plan

  assert {
    condition     = azurerm_kubernetes_cluster.this.azure_active_directory_role_based_access_control[0].tenant_id == var.tenant_id
    error_message = "the block must authenticate against the tenant the caller named, not one the provider infers"
  }

  # The default fixture passes no admin group. An empty list must reach the
  # cluster as an empty list -- not be dropped or defaulted to something
  # else that silently grants the built-in admin claim to nobody in
  # particular.
  assert {
    condition     = length(azurerm_kubernetes_cluster.this.azure_active_directory_role_based_access_control[0].admin_group_object_ids) == 0
    error_message = "with no admin group configured, the block must carry an empty list, meaning administration is granted by Azure role assignment alone"
  }
}

run "an_admin_group_reaches_the_cluster_when_the_caller_names_one" {
  command = plan

  # The positive half of the previous run's second assertion: a group the
  # caller does name must reach the block, not be swallowed the way an
  # empty default could mask either direction of a broken pass-through.
  variables {
    admin_group_object_ids = ["11111111-1111-1111-1111-111111111111"]
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.azure_active_directory_role_based_access_control[0].admin_group_object_ids == var.admin_group_object_ids
    error_message = "an admin group the caller names must reach the cluster's admin_group_object_ids unchanged"
  }
}

run "the_control_plane_may_manage_the_subnet_and_route_table_it_does_not_own" {
  # apply, not plan: azurerm_role_assignment carries no mock_resource entry of
  # its own, so its attributes -- even ones that are plain pass-throughs of an
  # already-known value -- stay unknown until the resource is actually
  # planned through to application.
  command = apply

  # Fails halfway through a ten minute apply if missing, with an error that
  # names neither the role nor the scope. Two separate grants, checked
  # separately: the defect that actually happens is one of the two missing or
  # landing at the wrong scope, and a combined assertion would not tell the
  # two apart.
  assert {
    condition     = azurerm_role_assignment.network_subnet.role_definition_name == "Network Contributor"
    error_message = "with userDefinedRouting the control plane must be able to read the subnet"
  }

  assert {
    condition     = azurerm_role_assignment.network_subnet.scope == var.subnet_id
    error_message = "the subnet role must be granted on the subnet itself, not somewhere wider"
  }

  assert {
    condition     = azurerm_role_assignment.network_route_table.role_definition_name == "Network Contributor"
    error_message = "with userDefinedRouting the control plane must be able to read the route table, which lives outside its node resource group"
  }

  assert {
    condition     = azurerm_role_assignment.network_route_table.scope == var.route_table_id
    error_message = "the route table role must be granted on the route table itself, not the resource group it lives in"
  }

  assert {
    condition     = azurerm_role_assignment.network_subnet.principal_id == azurerm_user_assigned_identity.control_plane.principal_id
    error_message = "both grants must name the control plane's own identity, not some other principal"
  }
}

run "the_cluster_uses_a_user_assigned_identity_created_before_it" {
  command = plan

  assert {
    condition     = azurerm_kubernetes_cluster.this.identity[0].type == "UserAssigned"
    error_message = "a system-assigned identity does not exist until the cluster does, which is backwards for granting it roles before creation"
  }

  assert {
    condition     = tolist(azurerm_kubernetes_cluster.this.identity[0].identity_ids) == tolist([azurerm_user_assigned_identity.control_plane.id])
    error_message = "the cluster must use the identity this module created for it, not a different one"
  }
}

run "there_is_no_policy_add_on_denying_nothing" {
  command = plan

  assert {
    condition     = azurerm_kubernetes_cluster.this.azure_policy_enabled == false
    error_message = "the add-on enforces nothing without a policy assignment targeting this cluster, and none exists; enabling it would only run an idle Gatekeeper deployment"
  }
}

run "the_cilium_data_plane_is_declared_as_a_pair" {
  command = plan

  # network_policy and network_data_plane must agree, or the provider itself
  # rejects the plan -- so what matters here is that both reach the profile,
  # not just one.
  assert {
    condition     = azurerm_kubernetes_cluster.this.network_profile[0].network_policy == "cilium"
    error_message = "network_policy must be cilium to match network_data_plane"
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.network_profile[0].network_data_plane == "cilium"
    error_message = "network_data_plane must be cilium to match network_policy"
  }
}

run "upgrades_are_channelled_rather_than_left_to_chance" {
  command = plan

  assert {
    condition     = azurerm_kubernetes_cluster.this.automatic_upgrade_channel == "patch"
    error_message = "without an automatic channel the cluster drifts out of support silently between sessions"
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.node_os_upgrade_channel == "NodeImage"
    error_message = "node images need their own refresh cadence, independent of the Kubernetes version"
  }

  assert {
    condition     = one(azurerm_kubernetes_cluster.this.maintenance_window_auto_upgrade).day_of_week == "Sunday"
    error_message = "an automatic upgrade window left undeclared can land during whatever hours the ingress path is actually being exercised"
  }

  assert {
    condition     = one(azurerm_kubernetes_cluster.this.maintenance_window_node_os).day_of_week == "Sunday"
    error_message = "the node OS refresh window must be declared for the same reason as the upgrade window"
  }
}

run "no_kubernetes_version_is_hardcoded" {
  command = plan

  # Asserted against the variable, not the mocked resource: the mock
  # provider invents a random placeholder for any optional string attribute
  # the config leaves null, which would make a resource-level assertion pass
  # or fail by coincidence rather than by checking what this module actually
  # sends.
  assert {
    condition     = var.kubernetes_version == null
    error_message = "the default must leave the version to Azure's own current default, not a literal that ages the day it is written"
  }
}

run "a_caller_may_still_pin_a_kubernetes_version" {
  command = plan

  variables {
    kubernetes_version = "1.29.2"
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.kubernetes_version == "1.29.2"
    error_message = "a caller naming a version must reach the cluster, not be silently dropped in favour of the default"
  }
}

run "the_nodes_may_pull_from_the_registry_without_a_pull_secret" {
  command = plan

  assert {
    condition     = azurerm_role_assignment.acr_pull.role_definition_name == "AcrPull"
    error_message = "check 5 requires the kubelet identity itself to be able to read the registry"
  }

  assert {
    condition     = azurerm_role_assignment.acr_pull.scope == var.acr_id
    error_message = "the pull right must be scoped to the registry, not to the whole subscription"
  }
}

run "the_tier_is_free_because_an_sla_buys_nothing_here" {
  command = plan

  assert {
    condition     = azurerm_kubernetes_cluster.this.sku_tier == "Free"
    error_message = "the Standard tier charges by the hour for an uptime guarantee no lab can claim against"
  }
}

run "the_node_pool_fits_the_quota" {
  command = plan

  assert {
    condition     = azurerm_kubernetes_cluster.this.default_node_pool[0].node_count == 1
    error_message = "a trial subscription has four regional vCPUs; a second two-vCPU node would not fit"
  }
}

run "a_non_canonical_pod_cidr_does_not_defeat_the_overlap_guard" {
  command = plan

  # pod_cidr names the address "10.61.0.0" but under /8 its real network base
  # is "10.60.0.0", which does overlap service_cidr below. A guard that takes
  # the address as written (split("/", cidr)[0]) misses this; one that masks
  # it (cidrhost(cidr, 0)) does not. dns_service_ip is kept inside the
  # service range as written so only the overlap guard is exercised.
  variables {
    pod_cidr       = "10.61.0.0/8"
    service_cidr   = "10.60.5.0/24"
    dns_service_ip = "10.60.5.10"
  }

  expect_failures = [var.service_cidr]
}

run "a_non_canonical_service_cidr_does_not_defeat_the_dns_containment_guard" {
  command = plan

  # service_cidr names the address "172.16.128.0" but under /16 its real
  # network base is "172.16.0.0", whose range excludes dns_service_ip below.
  variables {
    pod_cidr       = "192.168.0.0/16"
    service_cidr   = "172.16.128.0/16"
    dns_service_ip = "172.17.0.10"
  }

  expect_failures = [var.dns_service_ip]
}

run "the_upgrade_surge_is_declared_so_a_fresh_cluster_has_no_drift" {
  command = plan

  assert {
    condition     = one(azurerm_kubernetes_cluster.this.default_node_pool[0].upgrade_settings).max_surge == "10%"
    error_message = "Azure sets 10% on create; leaving it out makes every later plan propose removing it"
  }
}

# terraform_remote_state cannot be mocked with mock_data -- it is a builtin
# data source, not part of the azurerm provider -- so it is overridden
# directly with override_data instead. Every run in this file reads
# local.platform, so the override is declared at file scope rather than
# repeated in each run.
override_data {
  target = data.terraform_remote_state.platform

  values = {
    outputs = {
      location = "eastus2"

      hub_resource_group_name       = "rg-ops-alz-lab-eus2-01-hub"
      firewall_subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ops-alz-lab-eus2-01-hub/providers/Microsoft.Network/virtualNetworks/vnet-ops-alz-lab-eus2-01-hub/subnets/AzureFirewallSubnet"
      firewall_management_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ops-alz-lab-eus2-01-hub/providers/Microsoft.Network/virtualNetworks/vnet-ops-alz-lab-eus2-01-hub/subnets/AzureFirewallManagementSubnet"

      spoke_resource_group_name    = "rg-ops-alz-lab-eus2-01-spoke"
      spoke_route_table_name       = "rt-ops-alz-lab-eus2-01-spoke"
      spoke_route_table_id         = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ops-alz-lab-eus2-01-spoke/providers/Microsoft.Network/routeTables/rt-ops-alz-lab-eus2-01-spoke"
      spoke_default_route_next_hop = "10.60.0.4"
      spoke_address_space          = ["10.61.0.0/22"]
      pod_cidr                     = "192.168.0.0/16"

      application_security_group_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ops-alz-lab-eus2-01-hub/providers/Microsoft.Network/applicationSecurityGroups/asg-ops-alz-lab-eus2-01-cluster-reachable"

      subnet_ids = {
        cluster   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ops-alz-lab-eus2-01-spoke/providers/Microsoft.Network/virtualNetworks/vnet-ops-alz-lab-eus2-01-spoke/subnets/cluster"
        endpoints = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ops-alz-lab-eus2-01-spoke/providers/Microsoft.Network/virtualNetworks/vnet-ops-alz-lab-eus2-01-spoke/subnets/endpoints"
      }

      private_dns_zone_ids = {
        "privatelink.blob.core.windows.net" = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ops-alz-lab-eus2-01-spoke/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
        "privatelink.vaultcore.azure.net"   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ops-alz-lab-eus2-01-spoke/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"
        "privatelink.azurecr.io"            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ops-alz-lab-eus2-01-spoke/providers/Microsoft.Network/privateDnsZones/privatelink.azurecr.io"
      }

      key_vault_id       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ops-alz-lab-eus2-01-spoke/providers/Microsoft.KeyVault/vaults/kv-ops-alz-lab-eus2-01"
      storage_account_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ops-alz-lab-eus2-01-spoke/providers/Microsoft.Storage/storageAccounts/stopsalzlabeus201"

      workload_identity_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ops-alz-lab-eus2-01-spoke/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-ops-alz-lab-eus2-01"
      workload_identity_client_id    = "11111111-1111-1111-1111-111111111111"
      workload_identity_principal_id = "22222222-2222-2222-2222-222222222222"

      log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ops-alz-lab-eus2-01-spoke/providers/Microsoft.OperationalInsights/workspaces/log-ops-alz-lab-eus2-01"
    }
  }
}

mock_provider "azurerm" {
  # Asserting most outputs needs apply, because they carry identifiers the
  # provider computes. Under apply the mock generates short random ids and
  # azurerm rejects them while parsing wherever a schema validates an argument
  # as an Azure resource id -- so every type whose id is consumed that way by
  # this stack needs a structurally valid placeholder.
  mock_resource "azurerm_container_registry" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ops-alz-lab-eus2-01-spoke/providers/Microsoft.ContainerRegistry/registries/acropsalzlabeus201"
    }
  }

  mock_resource "azurerm_kubernetes_cluster" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ops-alz-lab-eus2-01-spoke/providers/Microsoft.ContainerService/managedClusters/aks-ops-alz-lab-eus2-01"
    }
  }

  mock_resource "azurerm_firewall" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ops-alz-lab-eus2-01-hub/providers/Microsoft.Network/azureFirewalls/afw-ops-alz-lab-eus2-01"
    }
  }

  mock_resource "azurerm_firewall_policy" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ops-alz-lab-eus2-01-hub/providers/Microsoft.Network/firewallPolicies/afwp-ops-alz-lab-eus2-01"
    }
  }

  mock_resource "azurerm_public_ip" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ops-alz-lab-eus2-01-hub/providers/Microsoft.Network/publicIPAddresses/pip-ops-alz-lab-eus2-01-fw"
      # A mocked computed attribute is a short random string by default, and
      # the firewall's NAT rule destination feeds this one straight into a
      # field the provider validates as an address. It rejects the random
      # value outright, which fails the whole file for a reason
      # that has nothing to do with what any run is asserting.
      #
      # RFC 5737 documentation range, never a real address.
      ip_address = "192.0.2.4"
    }
  }

  mock_resource "azurerm_private_endpoint" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ops-alz-lab-eus2-01-spoke/providers/Microsoft.Network/privateEndpoints/pe-ops-alz-lab-eus2-01"
    }
  }

  mock_resource "azurerm_key_vault_secret" {
    defaults = {
      id = "https://kv-ops-alz-lab-eus2-01.vault.azure.net/secrets/workload-probe-secret/00000000000000000000000000000000"
    }
  }

  mock_resource "azurerm_monitor_diagnostic_setting" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ops-alz-lab-eus2-01-hub/providers/Microsoft.Network/azureFirewalls/afw-ops-alz-lab-eus2-01/providers/microsoft.insights/diagnosticSettings/diag-ops-alz-lab-eus2-01-firewall"
    }
  }

  # The control plane's own identity, created inside module.aks and consumed
  # by the cluster's identity block.
  mock_resource "azurerm_user_assigned_identity" {
    defaults = {
      id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ops-alz-lab-eus2-01-spoke/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-ops-alz-lab-eus2-01-aks-control-plane"
      principal_id = "55555555-5555-5555-5555-555555555555"
    }
  }
}

variables {
  subscription_id = "00000000-0000-0000-0000-000000000000"
  tenant_id       = "11111111-1111-1111-1111-111111111111"

  prefix         = "ops"
  workload       = "alz"
  location_short = "eus2"

  platform_state_resource_group_name  = "rg-ops-bootstrap"
  platform_state_storage_account_name = "stopsbootstrap"
  platform_state_container_name       = "tfstate"
  platform_state_key                  = "lab/10-platform.tfstate"
}

run "the_federated_credential_trusts_the_clusters_own_issuer" {
  # module.aks.oidc_issuer_url is unknown until apply, so this run overrides
  # the cluster's realized issuer to a known value and checks the credential
  # actually carries it -- not some literal that happens to look right.
  #
  # This must be the first run in the file to touch module.aks: oidc_issuer_url
  # is a computed-only attribute with no argument, so once a later apply
  # creates the resource without this override, its realized value is fixed
  # for the rest of the file's shared state and no subsequent override_resource
  # will move it.
  command = apply

  override_resource {
    target = module.firewall.azurerm_firewall.this
    values = {
      # override_resource replaces the mock_resource-level default id for this
      # instance too, so it is restated here -- otherwise azurerm_monitor_
      # diagnostic_setting.firewall, which reads module.firewall.firewall_id
      # in every apply, fails to parse a short random mock id as an Azure
      # resource id.
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ops-alz-lab-eus2-01-hub/providers/Microsoft.Network/azureFirewalls/afw-ops-alz-lab-eus2-01"
      ip_configuration = {
        name                 = "data"
        private_ip_address   = "10.60.0.4"
        public_ip_address_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ops-alz-lab-eus2-01-hub/providers/Microsoft.Network/publicIPAddresses/pip-ops-alz-lab-eus2-01-fw"
        subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ops-alz-lab-eus2-01-hub/providers/Microsoft.Network/virtualNetworks/vnet-ops-alz-lab-eus2-01-hub/subnets/AzureFirewallSubnet"
      }
    }
  }

  override_resource {
    target = module.aks.azurerm_kubernetes_cluster.this
    values = {
      # Restated for the same reason as the firewall's: the override replaces
      # the mock default, and the deployer's role assignment parses this id.
      id              = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ops-alz-lab-eus2-01-spoke/providers/Microsoft.ContainerService/managedClusters/aks-ops-alz-lab-eus2-01"
      oidc_issuer_url = "https://eastus2.oic.prod-aks.azure.com/00000000-0000-0000-0000-000000000000/11111111-1111-1111-1111-111111111111/"
    }
  }

  # A hardcoded or wrong-source issuer would still be a string and still plan
  # clean; only comparing against the cluster's own realized value, and not
  # against a second copy of the same literal, catches that.
  assert {
    condition     = azurerm_federated_identity_credential.workload.issuer == module.aks.oidc_issuer_url
    error_message = "the credential must trust the cluster's own issuer, not a literal or a different source"
  }

  assert {
    condition     = tolist(azurerm_federated_identity_credential.workload.audience) == tolist(["api://AzureADTokenExchange"])
    error_message = "the audience is fixed by Azure; any other value fails the token exchange without a useful error"
  }
}

run "the_firewall_receives_the_address_the_platform_published" {
  # expected_private_ip is wired directly from local.platform, so there is
  # no separate variable left to compare against -- disagreement between the
  # two declarations is unrepresentable in the configuration, not merely
  # checked for. What remains to prove is that the value actually reaches the
  # firewall module. apply is required: the firewall module's own
  # postcondition on azurerm_firewall.this only evaluates once the resource's
  # attribute is realized.
  command = apply

  # override_resource values must be literals, so this pins the realized
  # address to "10.60.0.4" -- the same value the file-scope override_data above
  # publishes as spoke_default_route_next_hop. The postcondition on
  # azurerm_firewall.this compares this realized value against
  # var.expected_private_ip, i.e. against whatever main.tf actually wired. If
  # main.tf ever reverted to a literal that disagreed with local.platform, the
  # firewall module's own postcondition -- not this file -- would fail the
  # apply outright.
  override_resource {
    target = module.firewall.azurerm_firewall.this
    values = {
      # override_resource replaces the mock_resource-level default id for this
      # instance too, so it is restated here -- otherwise azurerm_monitor_
      # diagnostic_setting.firewall, which reads module.firewall.firewall_id
      # in every apply, fails to parse a short random mock id as an Azure
      # resource id.
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ops-alz-lab-eus2-01-hub/providers/Microsoft.Network/azureFirewalls/afw-ops-alz-lab-eus2-01"
      ip_configuration = {
        name                 = "data"
        private_ip_address   = "10.60.0.4"
        public_ip_address_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ops-alz-lab-eus2-01-hub/providers/Microsoft.Network/publicIPAddresses/pip-ops-alz-lab-eus2-01-fw"
        subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ops-alz-lab-eus2-01-hub/providers/Microsoft.Network/virtualNetworks/vnet-ops-alz-lab-eus2-01-hub/subnets/AzureFirewallSubnet"
      }
    }
  }

  assert {
    condition     = module.firewall.private_ip == local.platform.spoke_default_route_next_hop
    error_message = "the firewall must receive the same address the permanent layer's default route points at; a disagreement black-holes every flow while every check still looks green"
  }
}

run "the_diagnostic_setting_targets_the_firewall_and_the_workspace_it_was_given" {
  # apply is required: target_resource_id reads module.firewall.firewall_id, a
  # computed identifier unknown under plan.
  command = apply

  override_resource {
    target = module.firewall.azurerm_firewall.this
    values = {
      # override_resource replaces the mock_resource-level default id for this
      # instance too, so it is restated here -- otherwise azurerm_monitor_
      # diagnostic_setting.firewall, which reads module.firewall.firewall_id
      # in every apply, fails to parse a short random mock id as an Azure
      # resource id.
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ops-alz-lab-eus2-01-hub/providers/Microsoft.Network/azureFirewalls/afw-ops-alz-lab-eus2-01"
      ip_configuration = {
        name                 = "data"
        private_ip_address   = "10.60.0.4"
        public_ip_address_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ops-alz-lab-eus2-01-hub/providers/Microsoft.Network/publicIPAddresses/pip-ops-alz-lab-eus2-01-fw"
        subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ops-alz-lab-eus2-01-hub/providers/Microsoft.Network/virtualNetworks/vnet-ops-alz-lab-eus2-01-hub/subnets/AzureFirewallSubnet"
      }
    }
  }

  # Target and destination asserted separately, against the two different
  # resources' own identifiers rather than a second copy of the same literal:
  # a diagnostic setting pointed at the wrong resource, or shipping logs to
  # the wrong workspace, is still a structurally valid id and still plans
  # clean. A swap between the two arguments would pass a single combined
  # assertion but fails these.
  assert {
    condition     = azurerm_monitor_diagnostic_setting.firewall.target_resource_id == module.firewall.firewall_id
    error_message = "the diagnostic setting must watch this stack's own firewall, not some other resource"
  }

  assert {
    condition     = azurerm_monitor_diagnostic_setting.firewall.log_analytics_workspace_id == local.platform.log_analytics_workspace_id
    error_message = "the diagnostic setting must send to the workspace the platform layer published, not a different one"
  }

  assert {
    condition     = contains([for l in azurerm_monitor_diagnostic_setting.firewall.enabled_log : l.category], "AZFWNetworkRule")
    error_message = "network rule evaluations (service tag matches) must be logged"
  }

  assert {
    condition     = contains([for l in azurerm_monitor_diagnostic_setting.firewall.enabled_log : l.category], "AZFWApplicationRule")
    error_message = "application rule evaluations (FQDN tag matches) must be logged"
  }
}

run "the_registry_endpoint_fronts_the_registry" {
  # Checks the endpoint against its own echo-back outputs rather than against
  # the input fixture, so a crossed wire cannot pass unnoticed.
  #
  # apply is required: an endpoint carries identifiers the provider computes.
  command = apply

  override_resource {
    target = module.acr_endpoint.azurerm_private_endpoint.this
    values = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ops-alz-lab-eus2-01-spoke/providers/Microsoft.Network/privateEndpoints/pe-ops-alz-lab-eus2-01-registry"
    }
  }

  # The firewall module carries its own postcondition tying the realised
  # private address to var.expected_private_ip, which this stack's main.tf
  # wires directly from local.platform.spoke_default_route_next_hop -- the
  # address the platform layer's own default route already points at, read
  # from remote state rather than restated in a variable of this stack's own.
  # Under a mocked apply that address is not naturally the expected one, so it
  # is pinned here to the value the file-scope override_data above already
  # publishes as spoke_default_route_next_hop -- the same technique the
  # firewall module's own test suite uses for the same postcondition.
  override_resource {
    target = module.firewall.azurerm_firewall.this
    values = {
      # override_resource replaces the mock_resource-level default id for this
      # instance too, so it is restated here -- otherwise azurerm_monitor_
      # diagnostic_setting.firewall, which reads module.firewall.firewall_id
      # in every apply, fails to parse a short random mock id as an Azure
      # resource id.
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ops-alz-lab-eus2-01-hub/providers/Microsoft.Network/azureFirewalls/afw-ops-alz-lab-eus2-01"
      ip_configuration = {
        name                 = "data"
        private_ip_address   = "10.60.0.4"
        public_ip_address_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ops-alz-lab-eus2-01-hub/providers/Microsoft.Network/publicIPAddresses/pip-ops-alz-lab-eus2-01-fw"
        subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ops-alz-lab-eus2-01-hub/providers/Microsoft.Network/virtualNetworks/vnet-ops-alz-lab-eus2-01-hub/subnets/AzureFirewallSubnet"
      }
    }
  }

  # Asserted directly against what the module instance actually received, via
  # the echo-back outputs modules/private-endpoint exposes for exactly this
  # reason -- a target or zone swapped for a wrong-but-structurally-valid one
  # would still plan clean otherwise.
  assert {
    condition     = module.acr_endpoint.target_resource_id == module.acr.registry_id
    error_message = "the registry endpoint must front the registry, not some other target"
  }

  assert {
    condition     = module.acr_endpoint.private_dns_zone_id == local.platform.private_dns_zone_ids["privatelink.azurecr.io"]
    error_message = "the registry endpoint must register in the azurecr.io zone"
  }
}

run "two_nodes_are_refused_by_the_configuration" {
  command = plan

  variables {
    node_count = 2
  }

  expect_failures = [var.node_count]
}

run "the_cluster_is_wired_to_the_platforms_network_and_its_own_registry" {
  # AcrPull's scope is module.acr.registry_id, a computed identifier, unknown
  # until apply.
  command = apply

  override_resource {
    target = module.firewall.azurerm_firewall.this
    values = {
      # override_resource replaces the mock_resource-level default id for this
      # instance too, so it is restated here -- otherwise azurerm_monitor_
      # diagnostic_setting.firewall, which reads module.firewall.firewall_id
      # in every apply, fails to parse a short random mock id as an Azure
      # resource id.
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ops-alz-lab-eus2-01-hub/providers/Microsoft.Network/azureFirewalls/afw-ops-alz-lab-eus2-01"
      ip_configuration = {
        name                 = "data"
        private_ip_address   = "10.60.0.4"
        public_ip_address_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ops-alz-lab-eus2-01-hub/providers/Microsoft.Network/publicIPAddresses/pip-ops-alz-lab-eus2-01-fw"
        subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ops-alz-lab-eus2-01-hub/providers/Microsoft.Network/virtualNetworks/vnet-ops-alz-lab-eus2-01-hub/subnets/AzureFirewallSubnet"
      }
    }
  }

  assert {
    condition     = module.aks.node_pool_subnet_id == local.platform.subnet_ids["cluster"]
    error_message = "the node pool must attach to the platform's cluster subnet, not some other zone"
  }

  # Role and scope asserted separately for each of the two grants: a role
  # granted at the wrong scope is the defect that actually happens, and a
  # single combined assertion would not distinguish it from a wrong role at
  # the right scope.
  assert {
    condition     = module.aks.network_subnet_role_definition_name == "Network Contributor"
    error_message = "the control plane identity must hold Network Contributor on the subnet to read it with userDefinedRouting"
  }

  assert {
    condition     = module.aks.network_subnet_role_scope == local.platform.subnet_ids["cluster"]
    error_message = "the subnet grant must be scoped to the cluster subnet itself, not the resource group it lives in"
  }

  assert {
    condition     = module.aks.network_route_table_role_definition_name == "Network Contributor"
    error_message = "the control plane identity must hold Network Contributor on the route table to read it with userDefinedRouting"
  }

  assert {
    condition     = module.aks.network_route_table_role_scope == local.platform.spoke_route_table_id
    error_message = "the route table grant must be scoped to the route table itself, not the resource group it lives in"
  }

  assert {
    condition     = module.aks.acr_pull_role_definition_name == "AcrPull"
    error_message = "the kubelet identity must hold AcrPull to pull images without a pull secret"
  }

  assert {
    condition     = module.aks.acr_pull_role_scope == module.acr.registry_id
    error_message = "AcrPull must be scoped to this stack's own registry, not to the whole subscription or a different registry"
  }
}

run "the_federated_credentials_subject_is_built_from_the_two_variables" {
  # command = plan is enough here: the subject is a string interpolation of
  # two input variables, needing no computed attribute to evaluate.
  command = plan

  # Deliberately not the module's defaults (check4-probe / wi-probe): if the
  # subject were hardcoded to those defaults instead of built from the
  # variables, this run would still show a plausible-looking subject and only
  # asserting against these non-default values catches it.
  variables {
    workload_service_account_namespace = "custom-ns"
    workload_service_account_name      = "custom-sa"
  }

  assert {
    condition     = azurerm_federated_identity_credential.workload.subject == "system:serviceaccount:custom-ns:custom-sa"
    error_message = "the subject must be built from workload_service_account_namespace and workload_service_account_name, not a hardcoded default"
  }
}

run "the_workload_identity_holds_secrets_user_on_the_vault_and_nothing_wider" {
  command = plan

  # Role and scope asserted separately: a role granted at the wrong scope is
  # the defect that actually happens, and a single combined assertion would
  # not distinguish it from a wrong role at the right scope.
  assert {
    condition     = azurerm_role_assignment.workload_identity_vault_secrets_user.role_definition_name == "Key Vault Secrets User"
    error_message = "the workload identity must hold Key Vault Secrets User to read secrets by identity"
  }

  assert {
    condition     = azurerm_role_assignment.workload_identity_vault_secrets_user.scope == local.platform.key_vault_id
    error_message = "the grant must be scoped to the vault itself, not the resource group it lives in"
  }

  assert {
    condition     = azurerm_role_assignment.workload_identity_vault_secrets_user.principal_id == local.platform.workload_identity_principal_id
    error_message = "the grant must name the workload identity's own principal, not some other identity"
  }
}

run "the_stack_outputs_re_export_the_module_outputs_they_claim_to" {
  # Every output here carries an identifier the provider computes.
  command = apply

  override_resource {
    target = module.firewall.azurerm_firewall.this
    values = {
      # override_resource replaces the mock_resource-level default id for this
      # instance too, so it is restated here -- otherwise azurerm_monitor_
      # diagnostic_setting.firewall, which reads module.firewall.firewall_id
      # in every apply, fails to parse a short random mock id as an Azure
      # resource id.
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ops-alz-lab-eus2-01-hub/providers/Microsoft.Network/azureFirewalls/afw-ops-alz-lab-eus2-01"
      ip_configuration = {
        name                 = "data"
        private_ip_address   = "10.60.0.4"
        public_ip_address_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ops-alz-lab-eus2-01-hub/providers/Microsoft.Network/publicIPAddresses/pip-ops-alz-lab-eus2-01-fw"
        subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ops-alz-lab-eus2-01-hub/providers/Microsoft.Network/virtualNetworks/vnet-ops-alz-lab-eus2-01-hub/subnets/AzureFirewallSubnet"
      }
    }
  }

  assert {
    condition     = output.cluster_name == module.aks.cluster_name
    error_message = "cluster_name must come from the aks module"
  }

  assert {
    condition     = output.cluster_private_fqdn == module.aks.private_fqdn
    error_message = "cluster_private_fqdn must come from the aks module"
  }

  assert {
    condition     = output.oidc_issuer_url == module.aks.oidc_issuer_url
    error_message = "oidc_issuer_url must come from the aks module"
  }

  assert {
    condition     = output.registry_login_server == module.acr.login_server
    error_message = "registry_login_server must come from the acr module"
  }

  assert {
    condition     = output.firewall_public_ip == module.firewall.public_ip
    error_message = "firewall_public_ip must come from the firewall module"
  }

  assert {
    condition     = output.firewall_private_ip == module.firewall.private_ip
    error_message = "firewall_private_ip must come from the firewall module"
  }

  assert {
    condition     = output.federated_credential_subject == azurerm_federated_identity_credential.workload.subject
    error_message = "federated_credential_subject must come from the federated credential this stack creates"
  }
}

run "the_deployer_can_operate_the_cluster" {
  command = apply

  override_data {
    target = data.azurerm_client_config.current
    values = {
      object_id = "33333333-3333-3333-3333-333333333333"
    }
  }

  assert {
    condition     = azurerm_role_assignment.deployer_cluster_admin.role_definition_name == "Azure Kubernetes Service RBAC Cluster Admin"
    error_message = "local accounts are disabled, so without this role every kubectl call from the operator is Forbidden"
  }

  assert {
    condition     = azurerm_role_assignment.deployer_cluster_admin.principal_id == "33333333-3333-3333-3333-333333333333"
    error_message = "the grant must go to whoever runs Terraform, not to a fixed principal"
  }

  assert {
    condition     = azurerm_role_assignment.deployer_cluster_admin.scope == module.aks.cluster_id
    error_message = "the grant must be scoped to this cluster and nothing wider"
  }
}

run "the_firewalls_egress_rules_are_scoped_to_the_spoke_not_to_everywhere" {
  command = plan

  assert {
    condition     = tolist(module.firewall.allowed_source_addresses) == tolist(local.platform.spoke_address_space)
    error_message = "the service-tag and FQDN-tag rules must be sourced from the spoke's own address space, not from every address on the internet"
  }
}

run "the_registry_endpoint_joins_the_group_the_cluster_can_reach" {
  command = apply

  override_resource {
    target = module.firewall.azurerm_firewall.this
    values = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ops-alz-lab-eus2-01-hub/providers/Microsoft.Network/azureFirewalls/afw-ops-alz-lab-eus2-01"
      ip_configuration = {
        name                 = "data"
        private_ip_address   = "10.60.0.4"
        public_ip_address_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ops-alz-lab-eus2-01-hub/providers/Microsoft.Network/publicIPAddresses/pip-ops-alz-lab-eus2-01-fw"
        subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ops-alz-lab-eus2-01-hub/providers/Microsoft.Network/virtualNetworks/vnet-ops-alz-lab-eus2-01-hub/subnets/AzureFirewallSubnet"
      }
    }
  }

  assert {
    condition     = tolist(module.acr_endpoint.application_security_group_ids) == tolist([local.platform.application_security_group_id])
    error_message = "the registry's endpoint must join the same group the platform layer's vault endpoint joined, or the cluster's allow rule reaches nothing there"
  }
}

run "the_firewalls_resource_logs_land_in_their_own_tables" {
  command = apply

  override_resource {
    target = module.firewall.azurerm_firewall.this
    values = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ops-alz-lab-eus2-01-hub/providers/Microsoft.Network/azureFirewalls/afw-ops-alz-lab-eus2-01"
      ip_configuration = {
        name                 = "data"
        private_ip_address   = "10.60.0.4"
        public_ip_address_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ops-alz-lab-eus2-01-hub/providers/Microsoft.Network/publicIPAddresses/pip-ops-alz-lab-eus2-01-fw"
        subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ops-alz-lab-eus2-01-hub/providers/Microsoft.Network/virtualNetworks/vnet-ops-alz-lab-eus2-01-hub/subnets/AzureFirewallSubnet"
      }
    }
  }

  assert {
    condition     = azurerm_monitor_diagnostic_setting.firewall.log_analytics_destination_type == "Dedicated"
    error_message = "without Dedicated, both categories land in the shared AzureDiagnostics catch-all instead of their own typed, resource-specific tables"
  }
}

run "the_clusters_audit_trail_is_sent_to_the_workspace" {
  command = apply

  assert {
    condition     = azurerm_monitor_diagnostic_setting.aks.target_resource_id == module.aks.cluster_id
    error_message = "the diagnostic setting must watch this stack's own cluster, not some other resource"
  }

  assert {
    condition     = azurerm_monitor_diagnostic_setting.aks.log_analytics_workspace_id == local.platform.log_analytics_workspace_id
    error_message = "the diagnostic setting must send to the workspace the platform layer published"
  }

  assert {
    condition     = contains([for l in azurerm_monitor_diagnostic_setting.aks.enabled_log : l.category], "kube-audit-admin")
    error_message = "without kube-audit-admin, nothing records who called the Kubernetes API once local accounts are gone"
  }
}

run "the_workload_identity_can_push_images_to_its_own_registry" {
  command = apply

  assert {
    condition     = azurerm_role_assignment.workload_identity_acr_push.role_definition_name == "AcrPush"
    error_message = "check 5 needs the workload identity itself, not only the kubelet identity, to hold push rights on the registry"
  }

  assert {
    condition     = azurerm_role_assignment.workload_identity_acr_push.scope == module.acr.registry_id
    error_message = "the push right must be scoped to this stack's own registry, not to the whole subscription or a different one"
  }

  assert {
    condition     = azurerm_role_assignment.workload_identity_acr_push.principal_id == local.platform.workload_identity_principal_id
    error_message = "the grant must name the workload identity's own principal, not the kubelet identity or some other one"
  }
}

mock_provider "azurerm" {
  # modules/policy looks its definitions up through a data source, and azurerm
  # parses policy_definition_id at plan time. Without a structurally valid
  # placeholder every run here fails regardless of what the stack declares.
  mock_data "azurerm_policy_definition" {
    defaults = {
      id = "/providers/Microsoft.Authorization/policyDefinitions/00000000-0000-0000-0000-000000000000"
    }
  }

  # Asserting the outputs needs apply, because most of them carry identifiers
  # the provider computes. Under apply the mock generates short random ids and
  # azurerm rejects them while parsing, so each type whose id it parses needs a
  # structurally valid one. These seven are the types this stack reaches.
  mock_resource "azurerm_virtual_network" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet"
    }
  }

  mock_resource "azurerm_subnet" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet"
    }
  }

  mock_resource "azurerm_network_security_group" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/networkSecurityGroups/nsg"
    }
  }

  mock_resource "azurerm_route_table" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/routeTables/rt"
    }
  }

  mock_resource "azurerm_storage_account" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Storage/storageAccounts/stacct"
    }
  }

  # The private endpoints added for the vault and the object repository parse
  # both the target and the zone at apply time; each needs its own valid id.
  mock_resource "azurerm_key_vault" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.KeyVault/vaults/kv"
    }
  }

  mock_resource "azurerm_private_dns_zone" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/privateDnsZones/zone"
    }
  }

  mock_resource "azurerm_log_analytics_workspace" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.OperationalInsights/workspaces/log"
    }
  }

  # The vault and registry endpoints, and the group they join, all parse
  # their own id at apply time -- the vault endpoint's association with the
  # group reads both.
  mock_resource "azurerm_private_endpoint" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/privateEndpoints/pe"
    }
  }

  mock_resource "azurerm_application_security_group" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ops-alz-lab-eus2-01-hub/providers/Microsoft.Network/applicationSecurityGroups/asg-cluster-reachable"
    }
  }
}

# The blanket default above gives every zone the same id, which is enough for
# an endpoint to parse but not enough to tell zones apart -- the two zone
# pairing assertions below need the vault zone and the blob zone to actually
# differ, or a crossed wire between them would plan clean. These two
# overrides give only the zones the pairing test reads a distinct, valid id;
# every other zone keeps the shared default, which is fine because nothing
# asserts on them individually.
override_resource {
  target = module.private_dns.azurerm_private_dns_zone.this["privatelink.vaultcore.azure.net"]
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"
  }
}

override_resource {
  target = module.private_dns.azurerm_private_dns_zone.this["privatelink.blob.core.windows.net"]
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
  }
}

variables {
  prefix          = "ops"
  workload        = "alz"
  location        = "eastus2"
  location_short  = "eus2"
  subscription_id = "00000000-0000-0000-0000-000000000000"
  tenant_id       = "11111111-1111-1111-1111-111111111111"
}

run "the_two_zones_of_the_topology_exist" {
  command = plan

  # Only the two zones something in this landing zone actually attaches to.
  # A third, reserved-but-idle zone is a range nothing can ever hold
  # accountable.
  assert {
    condition = alltrue([
      for k in ["cluster", "endpoints"] :
      contains(keys(output.subnet_ids), k)
    ])
    error_message = "the spoke must carry cluster and endpoints"
  }

  assert {
    condition     = length(output.subnet_ids) == 2
    error_message = "no zone beyond cluster and endpoints should exist"
  }
}

run "the_stack_configures_the_endpoint_subnet_for_private_endpoints" {
  command = plan

  # Enabled, not Disabled: with policies enabled, the subnet's network
  # security group and the application security group its endpoints join are
  # actually evaluated against traffic to and from them, rather than
  # bypassed.
  assert {
    condition     = var.subnets["endpoints"].private_endpoint_network_policies == "Enabled"
    error_message = "a subnet holding private endpoints must enforce its own security group against them, or the group is decoration"
  }
}

run "egress_points_inside_the_firewall_subnet" {
  command = plan

  assert {
    condition     = cidrhost(cidrsubnet(var.hub_address_space[0], 2, 0), 4) == var.firewall_private_ip
    error_message = "the egress next hop must be the fourth address of the firewall subnet; Azure reserves the first four"
  }

  assert {
    condition     = tonumber(split("/", cidrsubnet(var.hub_address_space[0], 2, 0))[1]) <= 26
    error_message = "the firewall subnet must be /26 or larger, which Azure requires, or the address above does not exist"
  }
}

run "the_default_address_plan_is_accepted" {
  command = plan

  assert {
    condition     = output.location == var.location
    error_message = "the default hub and spoke ranges must pass the overlap guard"
  }
}

run "a_spoke_nested_inside_the_hub_is_refused_by_the_configuration" {
  command = plan

  # The case a string comparison misses: two different strings describing
  # overlapping addresses. This is refused by the variable's own validation,
  # so a direct apply is protected too, not only a test run.
  variables {
    hub_address_space   = ["10.60.0.0/16"]
    spoke_address_space = ["10.60.4.0/22"]
  }

  expect_failures = [var.spoke_address_space]
}

run "a_non_canonical_hub_cidr_does_not_defeat_the_overlap_guard" {
  command = plan

  # hub_address_space names the address "10.60.4.0" but under /16 its real
  # network base is "10.60.0.0", which fully contains the spoke below. A guard
  # that takes the address as written (split("/", cidr)[0]) misses this; one
  # that masks it (cidrhost(cidr, 0)) does not.
  variables {
    hub_address_space   = ["10.60.4.0/16"]
    spoke_address_space = ["10.60.0.0/22"]
  }

  expect_failures = [var.spoke_address_space]
}

run "the_outputs_expose_what_the_workload_stack_will_consume" {
  # The ephemeral workload stack consumes all eight of these and does not exist
  # yet to notice a crossed wiring. apply is required because most carry
  # computed identifiers, unknown under plan.
  command = apply

  assert {
    condition     = output.subnet_ids == module.spoke.subnet_ids
    error_message = "subnet identifiers must come from the spoke"
  }

  assert {
    condition     = output.private_dns_zone_ids == module.private_dns.zone_ids
    error_message = "zone identifiers must come from the private dns module"
  }

  assert {
    condition     = output.spoke_resource_group_name == module.spoke.resource_group_name
    error_message = "the group the workload stack builds into must come from the spoke"
  }

  assert {
    condition     = output.key_vault_id == module.keyvault.key_vault_id
    error_message = "the vault identifier must come from the vault"
  }

  assert {
    condition     = output.storage_account_id == module.storage.storage_account_id
    error_message = "the repository identifier must come from the repository"
  }

  assert {
    condition     = output.workload_identity_id == module.workload_identity.identity_id
    error_message = "the identity must come from the identity module"
  }

  assert {
    condition     = output.workload_identity_client_id == module.workload_identity.client_id
    error_message = "the client identifier must come from the identity module"
  }

  assert {
    condition     = output.location == var.location
    error_message = "the location output must report the region actually used"
  }

  assert {
    condition     = output.log_analytics_workspace_id == module.observability.workspace_id
    error_message = "the workspace identifier must come from the observability module"
  }

  assert {
    condition     = output.spoke_address_space == var.spoke_address_space
    error_message = "the spoke address space output must come from the spoke's own configured address space"
  }

  assert {
    condition     = output.application_security_group_id == azurerm_application_security_group.cluster_reachable.id
    error_message = "the group identifier output must come from the group this stack actually created"
  }
}

run "every_private_dns_zone_reaches_both_networks" {
  command = plan

  assert {
    condition     = length(keys(output.private_dns_zone_ids)) == length(var.private_dns_zone_names)
    error_message = "one zone per requested service, or that service resolves publicly"
  }
}

run "the_permanent_services_are_reachable_privately" {
  # Four pairings, not a count. The defect this catches is the vault endpoint
  # registered in the blob zone: both endpoints exist, both zone groups exist,
  # every count matches, and neither name resolves.
  command = apply

  assert {
    condition     = module.keyvault_endpoint.target_resource_id == module.keyvault.key_vault_id
    error_message = "the vault's endpoint must target the vault, not some other service"
  }

  assert {
    condition     = module.keyvault_endpoint.private_dns_zone_id == module.private_dns.zone_ids["privatelink.vaultcore.azure.net"]
    error_message = "the vault's endpoint must register in the vault zone"
  }

  assert {
    condition     = module.storage_endpoint.target_resource_id == module.storage.storage_account_id
    error_message = "the repository's endpoint must target the repository, not some other service"
  }

  assert {
    condition     = module.storage_endpoint.private_dns_zone_id == module.private_dns.zone_ids["privatelink.blob.core.windows.net"]
    error_message = "the repository's endpoint must register in the blob zone"
  }
}

run "the_permitted_flow_lands_in_the_subnet_its_key_names" {
  # Check 8 (scripts/verify/08-...) needs a real permitted flow to distinguish
  # "denied by policy" from "there is nothing there". The ASG-targeted rule
  # main.tf adds on top of var.allow_rules is that flow: the cluster subnet
  # reaching the endpoints subnet on 443, restricted further to only the
  # endpoints joined to the reachable group. subnet_key is exactly the field
  # a copy-paste gets wrong -- writing "cluster" here instead of "endpoints"
  # would leave the rule in the source subnet's own group, where it does
  # nothing to open the destination, and both subnets would stay
  # misconfigured while every count still matches.
  command = plan

  assert {
    condition     = module.spoke.allow_rule_security_group_names["cluster_to_reachable_endpoints_https"] == module.spoke.security_group_names["endpoints"]
    error_message = "the permitted flow must be written into the endpoints subnet's own security group"
  }

  assert {
    condition     = module.spoke.allow_rule_security_group_names["cluster_to_reachable_endpoints_https"] != module.spoke.security_group_names["cluster"]
    error_message = "the permitted flow must not land in a neighbour's security group -- the cluster subnet's own group is not where inbound traffic to the endpoints subnet is evaluated"
  }
}

run "the_cluster_reaches_itself_on_every_port_in_its_own_group" {
  # A multi-node cluster needs more between its own nodes than one port, so
  # the rule here is intra-subnet on every protocol and port: source and
  # destination are both the cluster subnet, and the rule must land in the
  # cluster subnet's own security group. subnet_key is exactly the field a
  # copy-paste gets wrong -- pointing it at a neighbour's group would leave
  # both subnets misconfigured while every count still matches, and the
  # traffic being intra-subnet means it never reaches the firewall to be
  # logged, so nothing short of this assertion would catch it.
  command = plan

  assert {
    condition     = module.spoke.allow_rule_security_group_names["cluster_to_cluster_all"] == module.spoke.security_group_names["cluster"]
    error_message = "the cluster's self-reach flow must be written into the cluster subnet's own security group"
  }
}

run "the_cluster_reaches_the_vault_and_registry_but_not_the_repository" {
  # The whole point of the reachable group: an allow rule naming it as a
  # destination, rather than the endpoints subnet's prefix, reaches only
  # whatever joined the group. This is what checks 4 and 5 depend on
  # succeeding while check 8's denied direction (the object repository) stays
  # blocked by the default deny.
  command = apply

  assert {
    condition     = tolist(module.spoke.allow_rule_destination_application_security_group_ids["cluster_to_reachable_endpoints_https"]) == tolist([azurerm_application_security_group.cluster_reachable.id])
    error_message = "the permitted flow must target the reachable group as its destination, not the whole endpoints subnet"
  }

  assert {
    condition     = tolist(module.keyvault_endpoint.application_security_group_ids) == tolist([azurerm_application_security_group.cluster_reachable.id])
    error_message = "the vault's endpoint must join the reachable group, or the cluster's allow rule reaches nothing there"
  }

  assert {
    condition     = length(module.storage_endpoint.application_security_group_ids) == 0
    error_message = "the object repository's endpoint must not join the reachable group -- it is meant to stay unreachable from the cluster, blocked by the default deny"
  }
}

run "the_spokes_routing_is_exposed_to_other_layers" {
  # Other layers read the route table through these outputs rather than by
  # name, so a rename cannot leave them pointing at nothing.
  command = apply

  assert {
    condition     = output.spoke_route_table_name == module.spoke.route_table_name
    error_message = "the route table name must come from the spoke"
  }
}

run "the_deployer_can_write_the_workload_secret" {
  command = apply

  override_data {
    target = data.azurerm_client_config.current
    values = {
      object_id = "33333333-3333-3333-3333-333333333333"
    }
  }

  assert {
    condition     = azurerm_role_assignment.deployer_vault_secrets.role_definition_name == "Key Vault Secrets Officer"
    error_message = "the workload stack writes a secret from the operator's machine and needs exactly this role"
  }

  assert {
    condition     = azurerm_role_assignment.deployer_vault_secrets.principal_id == "33333333-3333-3333-3333-333333333333"
    error_message = "the grant must go to whoever runs Terraform, not to a fixed principal"
  }

  assert {
    condition     = azurerm_role_assignment.deployer_vault_secrets.scope == module.keyvault.key_vault_id
    error_message = "the grant must be scoped to this vault and nothing wider"
  }
}

run "the_vaults_audit_trail_is_sent_to_the_workspace" {
  command = apply

  assert {
    condition     = azurerm_monitor_diagnostic_setting.keyvault.target_resource_id == module.keyvault.key_vault_id
    error_message = "the diagnostic setting must watch this stack's own vault, not some other resource"
  }

  assert {
    condition     = azurerm_monitor_diagnostic_setting.keyvault.log_analytics_workspace_id == module.observability.workspace_id
    error_message = "the diagnostic setting must send to this stack's own workspace"
  }

  assert {
    condition     = contains([for l in azurerm_monitor_diagnostic_setting.keyvault.enabled_log : l.category], "AuditEvent")
    error_message = "without AuditEvent, reads and writes on the vault's data plane are not logged anywhere"
  }
}

run "the_spoke_carries_vnet_flow_logs" {
  command = apply

  assert {
    condition     = azurerm_network_watcher_flow_log.spoke.target_resource_id == module.spoke.vnet_id
    error_message = "the flow log must watch the spoke's own virtual network, not some other one"
  }

  assert {
    condition     = azurerm_network_watcher_flow_log.spoke.storage_account_id == azurerm_storage_account.flow_logs.id
    error_message = "the flow log must write to this stack's own flow log storage account"
  }

  assert {
    condition     = azurerm_network_watcher_flow_log.spoke.enabled == true
    error_message = "a declared but disabled flow log records nothing while looking configured"
  }

  assert {
    condition     = one(azurerm_network_watcher_flow_log.spoke.retention_policy).days == 7
    error_message = "the retention window must be the one this design commits to, not whatever Azure defaults to"
  }

  assert {
    condition     = length(azurerm_network_watcher_flow_log.spoke.traffic_analytics) == 0
    error_message = "traffic analytics must stay off; declaring the block at all turns it on regardless of an enabled flag"
  }
}

run "no_budget_is_created_while_nobody_is_named_to_receive_it" {
  command = plan

  # The base variables carry no budget_contact_emails, which is the point:
  # this exercises the empty default.
  assert {
    condition     = length(azurerm_consumption_budget_subscription.this) == 0
    error_message = "a budget alert nobody receives is not a control and must not be created"
  }
}

run "a_budget_is_created_once_someone_is_named_to_receive_it" {
  command = plan

  variables {
    budget_contact_emails = ["ops@example.invalid"]
  }

  assert {
    condition     = length(azurerm_consumption_budget_subscription.this) == 1
    error_message = "naming a contact must actually create the budget, not merely accept the variable"
  }

  assert {
    condition     = one(azurerm_consumption_budget_subscription.this).amount == var.budget_amount
    error_message = "the budget must use the configured amount"
  }

  assert {
    condition = alltrue([
      for n in one(azurerm_consumption_budget_subscription.this).notification :
      n.contact_emails == tolist(var.budget_contact_emails)
    ])
    error_message = "every notification must reach the contacts the caller named"
  }

  assert {
    condition = (
      contains([for n in one(azurerm_consumption_budget_subscription.this).notification : n.threshold], 50) &&
      contains([for n in one(azurerm_consumption_budget_subscription.this).notification : n.threshold], 90) &&
      contains([for n in one(azurerm_consumption_budget_subscription.this).notification : n.threshold], 100)
    )
    error_message = "the budget must notify at 50 and 90 percent of actual spend and at 100 percent of the forecast"
  }
}

run "pods_on_different_nodes_can_reach_each_other" {
  command = plan

  assert {
    condition     = local.allow_rules["pod_to_pod"].source_address_prefix == var.pod_cidr
    error_message = "without an allow for the pod range, a second node's pods cannot reach DNS or anything on the first node"
  }

  assert {
    condition     = local.allow_rules["pod_to_pod"].destination_address_prefix == var.pod_cidr
    error_message = "the rule must admit pod to pod traffic, and only that"
  }

  assert {
    condition     = local.allow_rules["pod_to_pod"].priority < 4000
    error_message = "the allow must be evaluated before the deny at 4000"
  }

  assert {
    condition     = local.allow_rules["node_to_pod"].source_address_prefix == var.subnets["cluster"].address_prefix && local.allow_rules["node_to_pod"].destination_address_prefix == var.pod_cidr
    error_message = "nodes must be able to reach pods on other nodes"
  }
}

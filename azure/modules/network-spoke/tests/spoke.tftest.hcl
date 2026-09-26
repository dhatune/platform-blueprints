mock_provider "azurerm" {}

variables {
  name_prefix             = "ops-alz-lab-eus2-01"
  location                = "eastus2"
  address_space           = ["10.61.0.0/22"]
  hub_vnet_id             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/virtualNetworks/vnet-hub"
  hub_vnet_name           = "vnet-hub"
  hub_resource_group_name = "rg-hub"
  firewall_private_ip     = "10.60.0.4"
  tags                    = { environment = "lab" }

  subnets = {
    cluster   = { address_prefix = "10.61.1.0/24" }
    endpoints = { address_prefix = "10.61.2.0/27", private_endpoint_network_policies = "Enabled" }
  }
}

run "every_subnet_gets_its_own_security_group" {
  command = plan

  assert {
    condition     = length(azurerm_network_security_group.this) == 2
    error_message = "one security group per subnet, so rules never leak across zones"
  }

  assert {
    condition     = length(azurerm_subnet_network_security_group_association.this) == 2
    error_message = "every subnet must be associated to its security group"
  }
}

run "each_subnet_is_paired_with_its_own_security_group" {
  command = plan

  # Counting groups proves nothing about pairing. Pointing every subnet at one
  # shared group collapses the zone isolation this module exists to enforce and
  # leaves the counts identical. The deny rule carries the group name, which is
  # known at plan, so the pairing is checkable without resolving identifiers.
  assert {
    condition = alltrue([
      for k in keys(var.subnets) :
      azurerm_network_security_rule.deny_vnet_inbound[k].network_security_group_name == azurerm_network_security_group.this[k].name
    ])
    error_message = "each subnet's deny rule must be written into that subnet's own security group, not a shared one"
  }

  assert {
    condition     = length(distinct([for g in values(azurerm_network_security_group.this) : g.name])) == length(var.subnets)
    error_message = "every subnet must have a distinct security group; a shared one erases the zone boundary"
  }
}

run "an_explicit_allow_is_created_and_sorts_above_the_deny" {
  command = plan

  # allow_rules is the module's escape valve, and nothing in the tree had ever
  # populated it -- neither the resource nor its validation had been exercised.
  variables {
    allow_rules = {
      web-to-cluster = {
        subnet_key                 = "cluster"
        priority                   = 200
        direction                  = "Inbound"
        protocol                   = "Tcp"
        source_address_prefix      = "10.61.0.0/26"
        destination_address_prefix = "10.61.1.0/24"
        destination_port_range     = "8443"
        description                = "Web reaches the cluster over TLS."
      }
    }
  }

  assert {
    condition     = one(values(azurerm_network_security_rule.allow)).access == "Allow"
    error_message = "an explicit exception must allow, not deny"
  }

  assert {
    condition     = one(values(azurerm_network_security_rule.allow)).network_security_group_name == azurerm_network_security_group.this["cluster"].name
    error_message = "the exception must be written into the security group of the subnet it names"
  }
}

run "an_allow_at_the_deny_line_is_refused" {
  command = plan

  variables {
    allow_rules = {
      too-low = {
        subnet_key                 = "cluster"
        priority                   = 4000
        direction                  = "Inbound"
        protocol                   = "Tcp"
        source_address_prefix      = "10.61.0.0/26"
        destination_address_prefix = "10.61.1.0/24"
        destination_port_range     = "8443"
        description                = "Never reached."
      }
    }
  }

  expect_failures = [var.allow_rules]
}

run "every_security_group_denies_intra_network_traffic_by_default" {
  command = plan

  assert {
    condition     = alltrue([for r in values(azurerm_network_security_rule.deny_vnet_inbound) : r.access == "Deny"])
    error_message = "the default rule must deny, not allow"
  }

  assert {
    condition     = alltrue([for r in values(azurerm_network_security_rule.deny_vnet_inbound) : r.priority == 4000])
    error_message = "the deny rule must sit at 4000, below any explicit allow and above the Azure default at 65000"
  }

  assert {
    condition     = alltrue([for r in values(azurerm_network_security_rule.deny_vnet_inbound) : r.source_address_prefix == "VirtualNetwork"])
    error_message = "the deny rule must cover traffic originating inside the virtual network"
  }
}

run "private_endpoint_policies_are_honoured_per_subnet" {
  command = plan

  # Enabled, not Disabled: with policies enabled, the subnet's network
  # security group and application security groups are evaluated against
  # traffic to and from a private endpoint placed there, the same as for any
  # other resource in the subnet. Both subnets carry the same value here
  # because both need their own security group to actually mean something.
  assert {
    condition     = azurerm_subnet.this["endpoints"].private_endpoint_network_policies == "Enabled"
    error_message = "a subnet holding private endpoints must enforce its own security group against them, or the group is decoration"
  }

  assert {
    condition     = azurerm_subnet.this["cluster"].private_endpoint_network_policies == "Enabled"
    error_message = "subnets that did not ask for it must keep network policies enabled"
  }
}

run "an_allow_rule_can_target_an_application_security_group_instead_of_a_prefix" {
  command = plan

  variables {
    allow_rules = {
      cluster_to_asg = {
        subnet_key                                 = "endpoints"
        priority                                   = 200
        direction                                  = "Inbound"
        protocol                                   = "Tcp"
        source_address_prefix                      = "10.61.1.0/24"
        destination_application_security_group_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/applicationSecurityGroups/asg-reachable"]
        destination_port_range                     = "443"
        description                                = "Cluster reaches endpoints joined to the reachable group."
      }
    }
  }

  assert {
    condition     = azurerm_network_security_rule.allow["cluster_to_asg"].destination_application_security_group_ids == toset(["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/applicationSecurityGroups/asg-reachable"])
    error_message = "a rule naming an application security group must carry it through to the rule, not silently drop it"
  }

  assert {
    condition     = azurerm_network_security_rule.allow["cluster_to_asg"].destination_address_prefix == null
    error_message = "a rule targeting an application security group must not also carry a destination prefix"
  }
}

run "an_allow_rule_naming_neither_a_prefix_nor_a_group_is_refused" {
  command = plan

  variables {
    allow_rules = {
      broken = {
        subnet_key             = "endpoints"
        priority               = 200
        direction              = "Inbound"
        protocol               = "Tcp"
        source_address_prefix  = "10.61.1.0/24"
        destination_port_range = "443"
        description            = "Never reached; names no destination at all."
      }
    }
  }

  expect_failures = [var.allow_rules]
}

run "an_allow_rule_naming_both_a_prefix_and_a_group_is_refused" {
  command = plan

  variables {
    allow_rules = {
      broken = {
        subnet_key                                 = "endpoints"
        priority                                   = 200
        direction                                  = "Inbound"
        protocol                                   = "Tcp"
        source_address_prefix                      = "10.61.1.0/24"
        destination_address_prefix                 = "10.61.2.0/27"
        destination_application_security_group_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/applicationSecurityGroups/asg-reachable"]
        destination_port_range                     = "443"
        description                                = "Never reached; Azure rejects a rule carrying both."
      }
    }
  }

  expect_failures = [var.allow_rules]
}

run "egress_leaves_through_the_firewall" {
  command = plan

  assert {
    condition     = azurerm_route.default.next_hop_type == "VirtualAppliance"
    error_message = "the default route must hand egress to a virtual appliance, not to the internet"
  }

  assert {
    condition     = azurerm_route.default.next_hop_in_ip_address == "10.60.0.4"
    error_message = "the default route must point at the firewall private address supplied by the hub"
  }

  # There is deliberately no assertion that the table carries no inline route.
  # azurerm_route_table.route is computed, so it reads as unknown during a
  # plan and any condition over it is an error rather than a failure -- the
  # check cannot be written at this stage.
  #
  # The two assertions above cover the regression anyway. Moving the default
  # route back inside the table for tidiness means deleting
  # azurerm_route.default, and both conditions then reference a resource that
  # no longer exists, which fails loudly. That matters, because an inline
  # route block makes the table own its whole route set: the route the
  # ephemeral layer adds -- the one carrying replies to translated inbound
  # connections back out -- is then deleted on every apply of this stack.
}

run "peering_is_declared_in_both_directions" {
  command = plan

  assert {
    condition     = azurerm_virtual_network_peering.spoke_to_hub.remote_virtual_network_id == var.hub_vnet_id
    error_message = "the spoke must peer towards the hub"
  }

  assert {
    condition     = azurerm_virtual_network_peering.hub_to_spoke.virtual_network_name == var.hub_vnet_name
    error_message = "the hub side of the peering must be declared too, or the path is one way"
  }
}

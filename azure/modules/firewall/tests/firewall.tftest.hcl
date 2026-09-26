mock_provider "azurerm" {
  mock_resource "azurerm_firewall_policy" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/firewallPolicies/afwp"
    }
  }
}

# A single shared mock_resource default would give both public IPs the same
# id, which makes it impossible to tell "wired to the right address" apart
# from "wired to any address". Each gets its own override so the pairing
# assertions below can actually distinguish them.
#
# ip_address is pinned here too: left to the mock's own placeholder it is a
# random non-numeric string, and a NAT rule's destination_address goes
# through the provider's own valid-address check, so any run that plans a
# nat_rule_collection needs this to already be a syntactically valid address
# -- not a real one, an RFC 1918 range unrelated to any subnet this module
# declares.
override_resource {
  target = azurerm_public_ip.data
  values = {
    id         = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/publicIPAddresses/pip-data"
    ip_address = "10.99.99.4"
  }
}

override_resource {
  target = azurerm_public_ip.management
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/publicIPAddresses/pip-mgmt"
  }
}

variables {
  name_prefix              = "ops-alz-lab-eus2-01"
  location                 = "eastus2"
  resource_group_name      = "rg-ops-alz-lab-eus2-01-hub"
  subnet_id                = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/AzureFirewallSubnet"
  management_subnet_id     = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/AzureFirewallManagementSubnet"
  expected_private_ip      = "10.60.0.4"
  allowed_source_addresses = ["10.61.0.0/22"]
  tags                     = { environment = "lab" }

  allowed_service_tags = {
    control_plane = {
      protocols             = ["TCP"]
      destination_addresses = ["AzureCloud.eastus2"]
      destination_ports     = ["443"]
    }
  }

  allowed_fqdn_tags = ["AzureKubernetesService"]
}

run "the_tier_is_the_cheapest_that_is_still_a_firewall" {
  command = plan

  assert {
    condition     = azurerm_firewall.this.sku_tier == "Basic"
    error_message = "the lab runs Basic on purpose; Standard costs three times as much per hour"
  }

  assert {
    condition     = azurerm_firewall.this.sku_name == "AZFW_VNet"
    error_message = "a virtual network firewall, not a secured virtual hub"
  }
}

run "basic_gets_the_management_plane_it_requires" {
  command = apply

  # The lifecycle postcondition on azurerm_firewall.this fires on every apply.
  # Pin the data plane's mocked private_ip_address to the value the module's
  # own postcondition expects, so this run -- which is about the management
  # plane and the public IP pairing, not about that postcondition -- does not
  # fail for an unrelated reason.
  override_resource {
    target = azurerm_firewall.this
    values = {
      ip_configuration = {
        name                 = "data"
        private_ip_address   = "10.60.0.4"
        public_ip_address_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/publicIPAddresses/pip-data"
        subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/AzureFirewallSubnet"
      }
    }
  }

  # Basic refuses to deploy without this, and the failure arrives minutes into
  # an apply rather than at plan time.
  assert {
    condition     = length(azurerm_firewall.this.management_ip_configuration) == 1
    error_message = "Firewall Basic requires a management ip configuration"
  }

  # The two planes must not share an address. Wiring both configurations to the
  # same public IP is accepted by the schema and rejected by Azure.
  assert {
    condition     = azurerm_public_ip.data.name != azurerm_public_ip.management.name
    error_message = "the data and management planes need distinct public addresses"
  }

  # Distinct names is not the same claim as correctly paired. Wiring both
  # ip_configuration and management_ip_configuration to azurerm_public_ip.data
  # would still pass the assertion above while leaving azurerm_public_ip.management
  # declared and unused, so each configuration must be pinned to its own address.
  assert {
    condition     = azurerm_firewall.this.ip_configuration[0].public_ip_address_id == azurerm_public_ip.data.id
    error_message = "the data plane must attach to its own public ip"
  }

  assert {
    condition     = azurerm_firewall.this.management_ip_configuration[0].public_ip_address_id == azurerm_public_ip.management.id
    error_message = "the management plane must attach to its own public ip, not the data plane's"
  }
}

run "the_module_never_writes_a_name_into_a_network_rule" {
  command = plan

  # Basic has no DNS proxy, so a network rule written against an FQDN deploys
  # cleanly and matches nothing -- present, green and inert, the same failure
  # mode as a mistyped policy alias. This asserts on what the MODULE emits, so
  # it reddens if anyone later adds an FQDN passthrough.
  assert {
    condition = alltrue([
      for c in azurerm_firewall_policy_rule_collection_group.egress.network_rule_collection :
      alltrue([for r in c.rule : length(coalesce(r.destination_fqdns, [])) == 0])
    ])
    error_message = "a network rule with an FQDN destination is inert on Basic; the module must never emit one"
  }
}

run "a_two_label_hostname_that_is_not_a_known_tag_is_refused" {
  command = plan

  # docker.io is the case that matters: a two-label hostname is the same shape
  # as a two-label regional service tag ("Tag.Region"), so no regex can tell
  # them apart. Only the known-tag allowlist catches it. One destination per
  # run: expect_failures is satisfied if ANY entry in the map fails
  # validation, so a run carrying two invalid destinations would stay green
  # even if a regression re-admitted one of them.
  variables {
    allowed_service_tags = {
      docker = {
        protocols             = ["TCP"]
        destination_addresses = ["docker.io"]
        destination_ports     = ["443"]
      }
    }
  }

  expect_failures = [var.allowed_service_tags]
}

run "a_multi_label_registry_hostname_is_refused" {
  command = plan

  # The case a shape-only (regex) guard would catch, kept as its own run so
  # a regression here cannot hide behind the docker.io run passing.
  variables {
    allowed_service_tags = {
      docker_registry = {
        protocols             = ["TCP"]
        destination_addresses = ["registry-1.docker.io"]
        destination_ports     = ["443"]
      }
    }
  }

  expect_failures = [var.allowed_service_tags]
}

run "a_hostname_disguised_as_a_regional_tag_is_refused" {
  command = plan

  # The bypass of the previous (first-label-only) iteration of this guard.
  # "AzureCloud" really is a known tag, so checking only the first label
  # admits this. Splitting on "." yields three parts ("AzureCloud",
  # "evil-attacker-domain", "invalid"), not the two the region-tag shape (c)
  # requires, so the exact-shape validation refuses it.
  variables {
    allowed_service_tags = {
      spoofed = {
        protocols             = ["TCP"]
        destination_addresses = ["AzureCloud.evil-attacker-domain.invalid"]
        destination_ports     = ["443"]
      }
    }
  }

  expect_failures = [var.allowed_service_tags]
}

run "an_unpublished_tag_is_refused" {
  command = plan

  # A tag that merely looks plausible is not the same as a tag Microsoft
  # actually publishes. The allowlist must refuse what it does not recognise,
  # not just what looks like a hostname.
  variables {
    allowed_service_tags = {
      made_up = {
        protocols             = ["TCP"]
        destination_addresses = ["NotARealTag.eastus2"]
        destination_ports     = ["443"]
      }
    }
  }

  expect_failures = [var.allowed_service_tags]
}

run "a_real_service_tag_and_a_real_address_are_both_accepted" {
  command = plan

  # The other half. A validation that refuses everything would pass the test
  # above and make the module unusable.
  variables {
    allowed_service_tags = {
      regional = {
        protocols             = ["TCP"]
        destination_addresses = ["AzureCloud.eastus2"]
        destination_ports     = ["443"]
      }
      bare_tag = {
        protocols             = ["TCP"]
        destination_addresses = ["AzureActiveDirectory"]
        destination_ports     = ["443"]
      }
      literal = {
        protocols             = ["TCP"]
        destination_addresses = ["10.61.0.0/22"]
        destination_ports     = ["443"]
      }
    }
  }

  assert {
    condition     = length(azurerm_firewall_policy_rule_collection_group.egress.network_rule_collection[0].rule) == 3
    error_message = "service tags, regional service tags and literal ranges must all be accepted"
  }
}

run "a_tag_that_itself_contains_a_dot_is_accepted_by_exact_match" {
  command = plan

  # AzureFrontDoor.FirstParty is a real Microsoft service tag that itself
  # contains a dot. It is added to known_service_tags as that exact whole
  # string and accepted via branch (b), full-string equality -- not
  # decomposed into "AzureFrontDoor" plus a region, which branch (c) would
  # refuse anyway since "FirstParty" is not a bare lowercase-alphanumeric
  # region token.
  variables {
    known_service_tags = ["AzureFrontDoor.FirstParty"]
    allowed_service_tags = {
      frontdoor = {
        protocols             = ["TCP"]
        destination_addresses = ["AzureFrontDoor.FirstParty"]
        destination_ports     = ["443"]
      }
    }
  }

  assert {
    condition     = length(azurerm_firewall_policy_rule_collection_group.egress.network_rule_collection[0].rule) == 1
    error_message = "a service tag that contains a dot must be accepted by exact allowlist membership, not decomposed into a tag-plus-region shape"
  }
}

run "the_firewall_lands_on_the_address_the_permanent_layer_expects" {
  command = apply

  # The postcondition on azurerm_firewall.this only evaluates once the
  # resource's attributes are known, which requires an apply. This pins the
  # mocked private_ip_address to the value var.expected_private_ip already
  # carries, proving the postcondition does not spuriously fail when the two
  # genuinely agree.
  override_resource {
    target = azurerm_firewall.this
    values = {
      ip_configuration = {
        name                 = "data"
        private_ip_address   = "10.60.0.4"
        public_ip_address_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/publicIPAddresses/pip-data"
        subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/AzureFirewallSubnet"
      }
    }
  }

  assert {
    condition     = azurerm_firewall.this.ip_configuration[0].private_ip_address == var.expected_private_ip
    error_message = "the firewall's mocked private ip must match var.expected_private_ip for this run to prove anything"
  }
}

# The negative counterpart to the run above -- pinning the mock to an address
# that disagrees with var.expected_private_ip and expecting the postcondition
# to raise -- lives in tests/firewall_private_ip_mismatch.tftest.hcl. It needs
# a state of its own: terraform test carries applied state forward between run
# blocks in the SAME file, and azurerm_firewall.this's private_ip_address, once
# materialised by an apply, is not recomputed by a later run's override unless
# the resource is freshly created. Kept here it would silently inherit the
# already-matching value from the run above instead of exercising the override.

run "the_cluster_is_allowed_out_by_tag_not_by_hand" {
  command = plan

  assert {
    condition     = contains(var.allowed_fqdn_tags, "AzureKubernetesService")
    error_message = "without Microsoft's own tag the cluster cannot reach its control plane and never finishes provisioning"
  }
}

run "the_service_tag_rule_is_scoped_to_the_spoke_not_to_everywhere" {
  command = plan

  assert {
    condition     = tolist(azurerm_firewall_policy_rule_collection_group.egress.network_rule_collection[0].rule[0].source_addresses) == tolist(var.allowed_source_addresses)
    error_message = "a network rule sourced from \"*\" claims every address on the internet may originate this traffic, not only the spoke this firewall actually serves"
  }
}

run "the_fqdn_tag_rule_is_scoped_to_the_spoke_not_to_everywhere" {
  command = plan

  assert {
    condition = tolist(one([
      for c in azurerm_firewall_policy_rule_collection_group.egress.application_rule_collection :
      c if c.name == "allow-fqdn-tags"
    ]).rule[0].source_addresses) == tolist(var.allowed_source_addresses)
    error_message = "the Microsoft-maintained tag rule must be sourced from the spoke's own address space, the same as the service-tag network rule"
  }
}

run "no_nat_collection_exists_without_inbound_rules" {
  command = plan

  # The base variables block carries no inbound_nat_rules, so this exercises
  # the default {} -- the module must stay usable, and quiet, with no ingress.
  assert {
    condition     = length(azurerm_firewall_policy_rule_collection_group.egress.nat_rule_collection) == 0
    error_message = "a module with no inbound_nat_rules must not emit a nat_rule_collection"
  }
}

run "a_nat_rules_destination_is_the_firewalls_own_public_ip_not_a_caller_literal" {
  command = plan

  variables {
    inbound_nat_rules = {
      web = {
        protocols          = ["TCP"]
        source_addresses   = ["10.61.0.0/22"]
        destination_port   = "8443"
        translated_address = "10.60.1.10"
        translated_port    = 443
      }
    }
  }

  # Compared against the resource, not a literal: if the module ever starts
  # writing a caller-supplied or hardcoded address into destination_address,
  # this diverges from azurerm_public_ip.data.ip_address and reddens, even
  # though a literal string could coincidentally equal a mock's placeholder.
  assert {
    condition     = azurerm_firewall_policy_rule_collection_group.egress.nat_rule_collection[0].rule[0].destination_address == azurerm_public_ip.data.ip_address
    error_message = "a NAT rule's destination must be wired to the firewall's own public IP, not a value the caller passed in"
  }
}

run "each_nat_rule_translates_to_its_own_address_and_port_not_another_rules" {
  command = plan

  # Two rules with distinct pairs. A test that only counted rules or checked
  # the translated_port/translated_address values in isolation could still
  # pass if the module cross-wired web's port onto ssh's address; naming both
  # halves of each pair together is what catches that.
  variables {
    inbound_nat_rules = {
      web = {
        protocols          = ["TCP"]
        source_addresses   = ["10.61.0.0/22"]
        destination_port   = "8443"
        translated_address = "10.60.1.10"
        translated_port    = 443
      }
      ssh = {
        protocols          = ["TCP"]
        source_addresses   = ["10.61.0.0/22"]
        destination_port   = "2222"
        translated_address = "10.60.1.20"
        translated_port    = 22
      }
    }
  }

  assert {
    condition = (
      one([for r in azurerm_firewall_policy_rule_collection_group.egress.nat_rule_collection[0].rule : r if r.name == "web"]).translated_address == "10.60.1.10" &&
      one([for r in azurerm_firewall_policy_rule_collection_group.egress.nat_rule_collection[0].rule : r if r.name == "web"]).translated_port == 443 &&
      one([for r in azurerm_firewall_policy_rule_collection_group.egress.nat_rule_collection[0].rule : r if r.name == "ssh"]).translated_address == "10.60.1.20" &&
      one([for r in azurerm_firewall_policy_rule_collection_group.egress.nat_rule_collection[0].rule : r if r.name == "ssh"]).translated_port == 22
    )
    error_message = "each NAT rule must forward to its own translated_address/translated_port pair, not another rule's"
  }
}

run "a_nat_rule_without_explicit_source_addresses_is_refused" {
  command = plan

  # No permissive default exists to fall back to: an omitted (here, explicit
  # empty-list, which is what an omission resolves to via the variable's
  # optional() default) source list must fail validation rather than deploy
  # a NAT rule reachable from anywhere.
  variables {
    inbound_nat_rules = {
      web = {
        protocols          = ["TCP"]
        source_addresses   = []
        destination_port   = "8443"
        translated_address = "10.60.1.10"
        translated_port    = 443
      }
    }
  }

  expect_failures = [var.inbound_nat_rules]
}

run "no_named_host_collection_exists_without_entries" {
  command = plan

  # The base variables block carries no allowed_fqdns, so this exercises the
  # default {}. Only the Microsoft-maintained tag collection should be there.
  assert {
    condition = length([
      for c in azurerm_firewall_policy_rule_collection_group.egress.application_rule_collection :
      c if c.name == "allow-named-hosts"
    ]) == 0
    error_message = "a module with no allowed_fqdns must not emit a named-host collection"
  }
}

run "named_hosts_land_in_their_own_collection_over_both_web_protocols" {
  command = plan

  variables {
    allowed_fqdns = {
      source_repository = {
        destination_fqdns = ["example.invalid", "codeload.example.invalid"]
      }
    }
  }

  # Kept apart from the tag collection deliberately: reading the policy has to
  # separate what Microsoft maintains from what this landing zone decided,
  # because only one of those is ours to keep correct.
  assert {
    condition = one([
      for c in azurerm_firewall_policy_rule_collection_group.egress.application_rule_collection :
      c if c.name == "allow-named-hosts"
    ]).priority == 210
    error_message = "named hosts must occupy a collection of their own, after the tag collection"
  }

  # Wiring, not a literal: every host the caller named must reach the rule,
  # under the caller's own key.
  assert {
    condition = one([
      for r in one([
        for c in azurerm_firewall_policy_rule_collection_group.egress.application_rule_collection :
        c if c.name == "allow-named-hosts"
      ]).rule : r if r.name == "source_repository"
    ]).destination_fqdns == tolist(var.allowed_fqdns["source_repository"].destination_fqdns)
    error_message = "a named-host rule must carry exactly the hosts its caller named, under its caller's key"
  }

  # An application rule that serves only one of the two web protocols is the
  # kind of half-open door that reads as open: a repository fetched over
  # HTTPS fails while the rule sits there green.
  assert {
    condition = length(one([
      for r in one([
        for c in azurerm_firewall_policy_rule_collection_group.egress.application_rule_collection :
        c if c.name == "allow-named-hosts"
      ]).rule : r if r.name == "source_repository"
    ]).protocols) == 2
    error_message = "a named-host rule must permit both HTTP and HTTPS, or the half it omits fails against a rule that looks open"
  }
}

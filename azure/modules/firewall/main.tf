# Egress control for the whole landing zone.
#
# The SKU is Basic, which is the cheapest tier that is still a real firewall.
# Two of its limitations shape this module and neither is visible in the
# provider schema:
#
#   * no DNS proxy, therefore no FQDN filtering in NETWORK rules. Network
#     rules here take service tags or addresses only. An FQDN would be
#     accepted by Terraform and silently never match.
#   * threat intelligence is alert-only and cannot deny.
#
# FQDN *tags* in APPLICATION rules do work on Basic, and that is the mechanism
# the cluster relies on.

resource "azurerm_public_ip" "data" {
  name                = "pip-${var.name_prefix}-fw"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

# Basic runs its management plane on a second NIC that needs its own public
# address. This is not the egress address and no workload traffic uses it.
resource "azurerm_public_ip" "management" {
  name                = "pip-${var.name_prefix}-fw-mgmt"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_firewall_policy" "this" {
  name                = "afwp-${var.name_prefix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "Basic"
  tags                = var.tags

  # Deliberately no dns block: Basic has no DNS proxy. Declaring one is
  # rejected, and relying on one that is not there is how FQDN network rules
  # come to match nothing.
}

resource "azurerm_firewall_policy_rule_collection_group" "egress" {
  name               = "egress"
  firewall_policy_id = azurerm_firewall_policy.this.id
  priority           = 100

  dynamic "network_rule_collection" {
    for_each = length(var.allowed_service_tags) > 0 ? [1] : []

    content {
      name     = "allow-service-tags"
      priority = 100
      action   = "Allow"

      dynamic "rule" {
        for_each = var.allowed_service_tags

        content {
          name                  = rule.key
          protocols             = rule.value.protocols
          source_addresses      = var.allowed_source_addresses
          destination_addresses = rule.value.destination_addresses
          destination_ports     = rule.value.destination_ports
        }
      }
    }
  }

  dynamic "application_rule_collection" {
    for_each = length(var.allowed_fqdn_tags) > 0 ? [1] : []

    content {
      name     = "allow-fqdn-tags"
      priority = 200
      action   = "Allow"

      rule {
        name                  = "microsoft-maintained-tags"
        source_addresses      = var.allowed_source_addresses
        destination_fqdn_tags = var.allowed_fqdn_tags

        protocols {
          type = "Http"
          port = 80
        }

        protocols {
          type = "Https"
          port = 443
        }
      }
    }
  }

  # Named hosts this landing zone chose, kept in a collection of their own so
  # that reading the policy separates what Microsoft maintains from what we
  # decided. Only application rules can filter by name on this tier: a
  # network rule matching a name needs the DNS proxy the Basic tier lacks.
  dynamic "application_rule_collection" {
    for_each = length(var.allowed_fqdns) > 0 ? [1] : []

    content {
      name     = "allow-named-hosts"
      priority = 210
      action   = "Allow"

      dynamic "rule" {
        for_each = var.allowed_fqdns

        content {
          name              = rule.key
          source_addresses  = var.allowed_source_addresses
          destination_fqdns = rule.value.destination_fqdns

          protocols {
            type = "Http"
            port = 80
          }

          protocols {
            type = "Https"
            port = 443
          }
        }
      }
    }
  }

  # The chosen ingress path: destination-address translation on the address
  # the firewall already holds, not a second public address. The
  # subscription's public-address quota is three and the firewall's two
  # ip_configurations already spend two of it.
  dynamic "nat_rule_collection" {
    for_each = length(var.inbound_nat_rules) > 0 ? [1] : []

    content {
      name     = "inbound-nat"
      priority = 300
      action   = "Dnat"

      dynamic "rule" {
        for_each = var.inbound_nat_rules

        content {
          name             = rule.key
          protocols        = rule.value.protocols
          source_addresses = rule.value.source_addresses
          # Wired to the resource, never restated by the caller: a NAT rule's
          # destination is always the address this firewall itself holds, and
          # a caller-supplied literal here is exactly how the two drift apart.
          destination_address = azurerm_public_ip.data.ip_address
          destination_ports   = [rule.value.destination_port]
          translated_address  = rule.value.translated_address
          translated_port     = rule.value.translated_port
        }
      }
    }
  }
}

resource "azurerm_firewall" "this" {
  name                = "afw-${var.name_prefix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku_name            = "AZFW_VNet"
  sku_tier            = "Basic"
  firewall_policy_id  = azurerm_firewall_policy.this.id
  tags                = var.tags

  ip_configuration {
    name                 = "data"
    subnet_id            = var.subnet_id
    public_ip_address_id = azurerm_public_ip.data.id
  }

  management_ip_configuration {
    name                 = "management"
    subnet_id            = var.management_subnet_id
    public_ip_address_id = azurerm_public_ip.management.id
  }

  # The spoke's default route is written in the permanent layer before this
  # firewall exists, and it names a fixed address. Azure is free to assign the
  # data plane any usable address in its subnet; nothing in the schema ties it
  # to var.expected_private_ip. Without this check a firewall that lands on a
  # different address black-holes every flow while every other check in this
  # module still reports green.
  lifecycle {
    postcondition {
      condition     = self.ip_configuration[0].private_ip_address == var.expected_private_ip
      error_message = "The firewall's private IP does not match var.expected_private_ip. The permanent layer's default route already points at the expected address; a firewall landing elsewhere black-holes every flow while every other check still looks green."
    }
  }
}

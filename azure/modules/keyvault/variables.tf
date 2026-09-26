variable "name_prefix" {
  description = "Alphanumeric base name from the naming module. Key vault names reject most punctuation."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group the vault is created in."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "tenant_id" {
  description = "Entra tenant that owns the vault. Supplied by the caller; never discovered."
  type        = string
}

variable "sku_name" {
  description = "Vault tier. standard is sufficient unless hardware backed keys are required."
  type        = string
  default     = "standard"

  validation {
    condition     = contains(["standard", "premium"], var.sku_name)
    error_message = "sku_name must be standard or premium."
  }
}

variable "soft_delete_retention_days" {
  description = "Days a deleted secret can still be recovered."
  type        = number
  default     = 7

  validation {
    condition     = var.soft_delete_retention_days >= 7 && var.soft_delete_retention_days <= 90
    error_message = "Azure allows 7 to 90 days."
  }
}

variable "network_bypass" {
  description = <<-EOT
    Which trusted traffic may reach the vault around the deny-by-default rule.

    None is the closed posture this module claims, and the default. AzureServices
    opens a path for a class of first-party Azure services -- backup, disk
    encryption, and gateways reading certificates -- which is sometimes genuinely
    needed. Choosing it is never invisible: it means the vault is no longer
    reachable only through its private endpoint, and the module stops being able
    to make that claim.
  EOT
  type        = string
  default     = "None"

  validation {
    condition     = contains(["None", "AzureServices"], var.network_bypass)
    error_message = "network_bypass must be None or AzureServices."
  }
}

variable "tags" {
  description = "Tags produced by the naming module."
  type        = map(string)
}

variable "public_network_access_enabled" {
  description = <<-EOT
    Whether the vault answers on the public network at all. Closed by default.

    Closing the network plane locks out every caller regardless of role,
    including the owner and including Terraform: the network plane and the
    authorization plane are separate. Before setting this false, answer where
    Terraform runs from.
  EOT
  type        = bool
  default     = false
}

variable "allowed_ip_rules" {
  description = <<-EOT
    Addresses admitted when the public network is enabled. The default action
    stays Deny, so this is an allowlist and not a relaxation.
  EOT
  type        = list(string)
  default     = []

  validation {
    condition     = !var.public_network_access_enabled || length(var.allowed_ip_rules) > 0
    error_message = "Opening the public network without naming at least one address leaves the vault reachable by the whole internet behind RBAC alone. Name the addresses."
  }

  # This module's own guarantee, not a byproduct of azurerm's schema. An
  # empty string, a malformed string and an IPv6 literal are also refused by
  # azurerm's own validator on ip_rules, but a regex that only inspects a
  # trailing "/N" says nothing about what comes before it: a slashless entry
  # of "" or "not-an-ip" satisfies it trivially. Defense in
  # depth by accident is not a guarantee: if the provider ever loosened that
  # check, this module would admit garbage. So every entry is checked here,
  # in full, against dotted-quad IPv4 with an optional /0-32 suffix -- this
  # is what actually stands between a malformed entry and the resource, not
  # a neighbour's diligence.
  validation {
    condition = alltrue([
      for rule in var.allowed_ip_rules :
      can(regex(
        "^((25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\\.){3}(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])(/(3[0-2]|[12]?[0-9]))?$",
        rule
      ))
    ])
    error_message = "Each allowed_ip_rules entry must be a valid IPv4 address, optionally followed by a /0-32 CIDR suffix. Empty strings, malformed values and IPv6 literals are refused."
  }

  # A non-empty list is not the same claim as a narrow one: 0.0.0.0/0 names
  # every address, so "at least one entry" alone lets the whole internet in.
  # An operator exception is one machine or one small office range, so each
  # entry must be a bare address (a /32) or a CIDR no broader than /24.
  validation {
    condition = alltrue([
      for rule in var.allowed_ip_rules :
      can(regex("/(\\d+)$", rule)) ? tonumber(regex("/(\\d+)$", rule)[0]) >= 24 : true
    ])
    error_message = "Each allowed_ip_rules entry must be a single address or a CIDR no broader than /24 (one machine or one small office range). Wider prefixes such as 0.0.0.0/0, a /8, or a /16 are the public network with extra steps -- name the exception instead."
  }

  # Width alone is not enough: "203.0.113.5/24" is a valid, narrow-enough
  # entry by the rule above and still plans clean, but it names one host with
  # a /24 label stuck on it, not the /24 range an operator meant to admit --
  # azurerm accepts host bits set in ip_rules without complaint. An entry
  # must equal the network base of its own prefix. That base is taken with
  # cidrhost(rule, 0), the exact normalisation modules/aks's pod/service
  # overlap guard and live/lab/10-platform's hub/spoke overlap guard already
  # use to mask a CIDR down to its network address -- this is the same
  # comparison, not a different one written for this module alone. A bare
  # address has no prefix to violate: it is always treated as /32 below, and
  # every /32 is trivially its own network base, so it passes without
  # reaching cidrhost.
  #
  # cidrhost() itself throws a raw "invalid CIDR address" function error on
  # any prefix wider than /32, or on a non-numeric one -- it has no notion of
  # IPv4's own ceiling. The validation above already refuses anything wider
  # than /24, so a /33 never reaches production with this bypassed, but it
  # can still reach this validation's own evaluation: Terraform evaluates
  # every validation block's condition against every value regardless of
  # which block is meant to reject it, so a crash in this block's expression
  # drowns out a clean error_message from another block for the same entry.
  # Only the ternary operator is lazy in Terraform -- "&&" evaluates both
  # sides regardless of the left one's result -- so the prefix is validated
  # with nested ternaries, the same lazy pattern the /24-width check above
  # already relies on, rather than a guard clause joined with "&&". The
  # inner cidrhost(rule, 0) is reached only once the prefix is confirmed
  # both numeric and <= 32, so it always receives a well-formed CIDR.
  validation {
    condition = alltrue([
      for rule in var.allowed_ip_rules :
      !can(regex("/", rule)) ? true : (
        can(regex("/(\\d+)$", rule))
        ? (
          tonumber(regex("/(\\d+)$", rule)[0]) <= 32
          ? cidrhost(rule, 0) == split("/", rule)[0]
          : false
        )
        : false
      )
    ])
    error_message = "Each allowed_ip_rules entry with a /prefix must be the network base of that prefix (e.g. 203.0.113.0/24, not 203.0.113.5/24 -- the host bits must be zero), and the prefix itself must be a number from 0 to 32. A bare address is always accepted as /32."
  }
}

variable "name_prefix" {
  description = "Base name produced by the naming module."
  type        = string
}

variable "location" {
  description = "Azure region. No default on purpose."
  type        = string
}

variable "address_space" {
  description = "Address space of the spoke. Must not overlap the hub or any on-premises range."
  type        = list(string)
}

variable "subnets" {
  description = <<-EOT
    Subnets of the spoke, keyed by logical name. The key is what other modules
    use to ask for a subnet, so it must describe the zone, not the product that
    happens to live there.

    private_endpoint_network_policies should be Enabled on any subnet that will
    hold private endpoints: with it enabled, the subnet's own network security
    group and application security groups are evaluated against traffic to and
    from the endpoint, the same as for any other resource in the subnet. Left
    Disabled, a private endpoint bypasses the subnet's NSG entirely, which is
    the opposite of the deny-by-default posture this module exists to enforce.
  EOT

  type = map(object({
    address_prefix                    = string
    private_endpoint_network_policies = optional(string, "Enabled")
    service_endpoints                 = optional(list(string), [])
  }))

  validation {
    condition = alltrue([
      for s in values(var.subnets) :
      contains(["Enabled", "Disabled", "NetworkSecurityGroupEnabled", "RouteTableEnabled"], s.private_endpoint_network_policies)
    ])
    error_message = "private_endpoint_network_policies must be one of Enabled, Disabled, NetworkSecurityGroupEnabled or RouteTableEnabled."
  }
}

variable "allow_rules" {
  description = <<-EOT
    Explicit exceptions to the default deny, keyed by an arbitrary rule name.
    subnet_key says which security group the rule is written into. Priority must
    be below 4000 so the rule is evaluated before the deny.
  EOT

  type = map(object({
    subnet_key            = string
    priority              = number
    direction             = string
    protocol              = string
    source_address_prefix = string
    description           = string

    # Exactly one of these. A rule reaches a private endpoint either by naming
    # the subnet it sits in, or by naming an application security group the
    # endpoint has joined -- the second is how a rule can single out one
    # endpoint among several sharing the same subnet, which an address prefix
    # cannot do.
    destination_address_prefix                 = optional(string)
    destination_application_security_group_ids = optional(list(string))

    # Exactly one of these. Azure's rule object carries both a singular port
    # and a plural list and rejects a rule that sets both, so this module
    # cannot simply always use the list: it has to pass whichever the caller
    # gave and leave the other null. A rule needing two ports that are not
    # adjacent -- 80 and 443, the usual case -- has no way to say so through
    # the singular field, and writing it as the range 80-443 would open the
    # 362 ports in between.
    destination_port_range  = optional(string)
    destination_port_ranges = optional(list(string))
  }))

  default = {}

  validation {
    condition = alltrue([
      for r in values(var.allow_rules) :
      (r.destination_port_range == null) != (r.destination_port_ranges == null)
    ])
    error_message = "each allow rule must set exactly one of destination_port_range or destination_port_ranges; Azure rejects a rule carrying both, and a rule carrying neither opens nothing."
  }

  validation {
    condition = alltrue([
      for r in values(var.allow_rules) :
      (r.destination_address_prefix == null) != (r.destination_application_security_group_ids == null)
    ])
    error_message = "each allow rule must set exactly one of destination_address_prefix or destination_application_security_group_ids; a rule carrying both is rejected by Azure, and a rule carrying neither reaches nothing."
  }

  # Azure allows 100 to 4096. The upper bound here is tighter on purpose: an
  # allow at 4000 or above would sort at or below the default deny and never
  # be reached.
  # Azure caps a rule description at 140 characters and rejects a longer one
  # at apply time, after everything before it in the graph has been created.
  # Checking here turns that into a plan error instead.
  validation {
    condition     = alltrue([for r in values(var.allow_rules) : length(r.description) <= 140])
    error_message = "an allow rule description must be at most 140 characters; Azure rejects longer ones at apply time, once the rest of the network already exists."
  }

  validation {
    condition     = alltrue([for r in values(var.allow_rules) : r.priority >= 100 && r.priority < 4000])
    error_message = "allow rules must sit between 100 and 3999, so they are evaluated before the default deny at 4000."
  }
}

variable "hub_vnet_id" {
  description = "Identifier of the hub virtual network to peer with."
  type        = string
}

variable "hub_vnet_name" {
  description = "Name of the hub virtual network, needed to declare the hub side of the peering."
  type        = string
}

variable "hub_resource_group_name" {
  description = "Resource group of the hub, needed to declare the hub side of the peering."
  type        = string
}

variable "firewall_private_ip" {
  description = <<-EOT
    Private address of the firewall that egress is routed to. Supplied by the
    caller rather than discovered, so the spoke can be planned before the
    firewall exists.
  EOT
  type        = string
}

variable "tags" {
  description = "Tags produced by the naming module."
  type        = map(string)
}

variable "name_prefix" {
  description = "Base name produced by the naming module."
  type        = string
}

variable "location" {
  description = "Azure region. Deliberately has no default: choosing a region has data residency consequences."
  type        = string
}

variable "address_space" {
  description = "Address space of the hub virtual network. Must not overlap any spoke or on-premises range."
  type        = list(string)

  validation {
    condition     = length(var.address_space) > 0
    error_message = "the hub needs at least one address space."
  }

  # The reserved subnets are derived two bits down from this space. A space
  # smaller than /24 therefore yields subnets below the /26 floor Azure
  # enforces, and it does so silently: cidrsubnet is happy to produce a /28.
  validation {
    condition     = alltrue([for cidr in var.address_space : tonumber(split("/", cidr)[1]) <= 24])
    error_message = "Each address space must be /24 or larger, or the reserved subnets fall below the /26 minimum Azure requires."
  }
}

variable "tags" {
  description = "Tags produced by the naming module."
  type        = map(string)
}

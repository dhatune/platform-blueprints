variable "name_prefix" {
  description = "Base name produced by the naming module."
  type        = string
}

variable "registry_base" {
  description = <<-EOT
    Alphanumeric base for the registry name. Azure allows only letters and
    digits here, between 5 and 50 characters, globally unique.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9]+$", var.registry_base))
    error_message = "A registry name may contain only letters and digits; hyphens and underscores are rejected."
  }
}

variable "location" {
  description = "Azure region. No default on purpose."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group the registry is created in."
  type        = string
}

variable "tags" {
  description = "Tags produced by the naming module."
  type        = map(string)
}

variable "prefix" {
  description = "Short organisation prefix used to open every resource name."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{2,6}$", var.prefix))
    error_message = "prefix must be 2 to 6 lowercase alphanumeric characters."
  }
}

variable "workload" {
  description = "Short workload identifier, for example the platform or the application it serves."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{2,8}$", var.workload))
    error_message = "workload must be 2 to 8 lowercase alphanumeric characters."
  }
}

variable "environment" {
  description = <<-EOT
    Deployment profile this name belongs to, for example "lab". Validated the
    same generic way as prefix, workload and location_short -- a shape check,
    not a fixed list of named profiles this module claims to know about. This
    repository ships one profile, live/lab; naming a second one here would
    describe a composition that does not exist anywhere in this tree.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{2,8}$", var.environment))
    error_message = "environment must be 2 to 8 lowercase alphanumeric characters."
  }
}

variable "location_short" {
  description = "Abbreviated Azure region, for example eus2. Kept separate from the region itself so names stay short."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{2,6}$", var.location_short))
    error_message = "location_short must be 2 to 6 lowercase alphanumeric characters."
  }
}

variable "instance" {
  description = "Instance discriminator, so a second copy of the same scope can coexist."
  type        = string
  default     = "01"

  validation {
    condition     = can(regex("^[0-9]{2}$", var.instance))
    error_message = "instance must be two digits."
  }
}

variable "extra_tags" {
  description = "Additional tags merged on top of the required ones. Cannot displace the required keys."
  type        = map(string)
  default     = {}
}

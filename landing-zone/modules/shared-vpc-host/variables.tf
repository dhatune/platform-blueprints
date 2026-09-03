variable "project_id" {
  description = "Project ID of the Shared VPC host project."
  type        = string
}

variable "region" {
  description = "Region for the subnets."
  type        = string
}

variable "networks" {
  description = <<-EOT
    One entry per environment. Each becomes a physically separate VPC.

    They are separate networks rather than separate subnets of one network,
    and they are not peered. See ADR 4: the isolation is the feature, and the
    cost is that anything shared between environments has to be built twice.
  EOT
  type = map(object({
    subnet_cidr = string
  }))

  validation {
    condition     = length(var.networks) > 0
    error_message = "Declare at least one network."
  }

  validation {
    condition = alltrue([
      for name, net in var.networks : can(cidrhost(net.subnet_cidr, 0))
    ])
    error_message = "Every subnet_cidr must be a valid CIDR block."
  }
}

variable "internal_ingress_ports" {
  description = "TCP ports reachable from inside the same subnet."
  type        = list(string)
  default     = ["22", "443"]
}

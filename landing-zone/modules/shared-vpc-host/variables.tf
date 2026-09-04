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

    # Secondary ranges, needed by anything that assigns addresses from the
    # subnet rather than to it: a VPC-native Kubernetes cluster being the
    # usual reason, since it draws pod and service addresses from here.
    #
    # Optional because not every environment runs one, and empty because a
    # default set of ranges would silently consume address space that the
    # caller may have planned for something else.
    secondary_ranges = optional(map(string), {})
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

variable "health_check_ranges" {
  description = <<-EOT
    Source ranges the platform's load balancer probes come from. These are
    fixed and published; they are listed rather than hardcoded so that a
    different platform, or a change to them, is a value and not an edit.
  EOT
  type        = list(string)
  default     = ["35.191.0.0/16", "130.211.0.0/22"]
}

variable "health_check_ports" {
  description = <<-EOT
    Ports the probes are allowed to reach. Kept to what workloads actually
    serve on: allowing every port would make the probe ranges a general path
    into the network rather than a narrow one.
  EOT
  type        = list(string)
  default     = ["80", "443", "8080"]
}

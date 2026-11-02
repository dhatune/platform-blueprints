variable "project_id" {
  description = "GCP project that hosts the PoC (created by bootstrap/)."
  type        = string
}

variable "region" {
  description = "GCP region."
  type        = string
  default     = "us-east1"
}

variable "zone" {
  description = "GCP zone for all VMs."
  type        = string
  default     = "us-east1-b"
}

variable "admin_cidrs" {
  description = "Public ranges allowed to reach the AAP web UI. Each must be /28 or narrower (networks with several egress IPs need a small range instead of a single /32)."
  type        = list(string)

  validation {
    condition = length(var.admin_cidrs) > 0 && length(var.admin_cidrs) <= 4 && alltrue([
      for c in var.admin_cidrs : can(cidrhost(c, 0)) && tonumber(split("/", c)[1]) >= 28
    ])
    error_message = "admin_cidrs must hold 1 to 4 ranges, each /28 or narrower (never 0.0.0.0/0)."
  }
}

variable "ssh_public_key" {
  description = "Public key installed for the 'ansible' user on every VM."
  type        = string
}

variable "ssh_user" {
  description = "OS user the controller uses to reach managed nodes."
  type        = string
  default     = "ansible"
}

variable "subnet_cidr" {
  description = "Primary range of the PoC subnet."
  type        = string
  default     = "10.30.0.0/24"
}

variable "gateway_https_port" {
  description = "HTTPS port of the AAP platform entry point (Envoy gateway proxy). The installer lowers ip_unprivileged_port_start to 80, so rootless Podman binds 443."
  type        = number
  default     = 443
}

variable "project_id" {
  description = "Project ID to create. Must be globally unique."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be 6-30 characters, lowercase letters, digits and hyphens."
  }
}

variable "display_name" {
  description = <<-EOT
    Human-readable project name.

    The accepted character set is narrower than it looks: letters, digits,
    hyphen, apostrophe, quote, space and exclamation mark. An em dash or an
    accented character copied from a design document is rejected, which is a
    classic first-apply failure.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9'\" !-]{4,30}$", var.display_name))
    error_message = "display_name may only contain letters, digits, hyphen, apostrophe, quote, space and exclamation mark."
  }
}

variable "folder_id" {
  description = "Parent folder, as folders/NNN."
  type        = string
}

variable "billing_account" {
  description = "Billing account to attach."
  type        = string
  sensitive   = true
}

variable "shared_vpc_host_project" {
  description = "Host project to attach to. Leave null for a standalone project."
  type        = string
  default     = null
}

variable "subnet_grants" {
  description = <<-EOT
    Subnets this project may use, and the principals allowed to use them.

    Granting compute.networkUser on a single subnet rather than on the whole
    host project is what keeps a service project from reaching networks that
    belong to a different product.
  EOT
  type = list(object({
    subnet_id = string
    region    = string
    members   = list(string)
  }))
  default = []
}

variable "activate_apis" {
  description = "APIs to enable. Keep the list minimal and add on demand."
  type        = list(string)
  default     = []
}

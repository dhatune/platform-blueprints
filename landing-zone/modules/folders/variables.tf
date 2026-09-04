variable "organization_id" {
  description = "Numeric organisation ID that owns the hierarchy."
  type        = string

  validation {
    condition     = can(regex("^[0-9]+$", var.organization_id))
    error_message = "organization_id must be numeric, without the organizations/ prefix."
  }
}

variable "root_folder_name" {
  description = "Display name of the folder that holds everything else."
  type        = string
  default     = "platform"
}

variable "product_folders" {
  description = <<-EOT
    Display names of the per-product folders, one per product.

    A folder per product is what makes least privilege affordable: an operator
    is granted a role on one folder rather than on the organisation, and the
    blast radius of a mistake stops at the folder boundary.
  EOT
  type        = list(string)

  validation {
    condition     = length(var.product_folders) > 0
    error_message = "Declare at least one product folder."
  }
}

variable "deletion_protection" {
  description = <<-EOT
    Whether folders refuse to be destroyed. True everywhere that matters.

    It is a variable rather than a constant because a blueprint that cannot be
    torn down cannot be tried, and something nobody can try gets adopted
    without being understood.
  EOT
  type        = bool
  default     = true
}

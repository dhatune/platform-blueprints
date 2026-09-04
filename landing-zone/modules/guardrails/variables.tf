variable "parent" {
  description = "Where the constraints apply, as organizations/<id> or folders/<id>."
  type        = string

  validation {
    condition     = can(regex("^(organizations|folders)/[0-9]+$", var.parent))
    error_message = "Must be organizations/<numeric id> or folders/<numeric id>."
  }
}

variable "allowed_customer_ids" {
  description = <<-EOT
    Cloud Identity customer IDs permitted in IAM policies. These are IDs of the
    form C0xxxxxxx, not domain names: a domain name here yields a policy that
    matches nothing and reports success.
  EOT
  type        = list(string)

  validation {
    condition     = alltrue([for c in var.allowed_customer_ids : can(regex("^C[a-z0-9]+$", c))])
    error_message = "Expected Cloud Identity customer IDs (C0xxxxxxx), not domain names."
  }
}

variable "exempt_folders" {
  description = <<-EOT
    Folder ids exempted from the automatic-grants constraint, for workloads
    whose managed build process depends on those grants. Keep this list short
    and revisit it; each entry is a hole with a reason.
  EOT
  type        = list(string)
  default     = []
}

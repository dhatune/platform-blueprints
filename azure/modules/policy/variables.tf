variable "name_prefix" {
  description = <<-EOT
    Leads both assignment names. Assignments live at subscription scope, so two
    landing zones in one subscription would otherwise claim the same names, and
    a check could pass on the other deployment's policy instead of this one's.
  EOT
  type        = string
}

variable "subscription_id" {
  description = "Subscription the policies are assigned to. Supplied by the caller; never discovered."
  type        = string
}

variable "allowed_locations" {
  description = <<-EOT
    Regions resources may be created in. Restricting this is the cheapest control
    against data landing in a jurisdiction nobody agreed to.
  EOT
  type        = list(string)

  validation {
    condition     = length(var.allowed_locations) > 0
    error_message = "at least one region must be allowed, or nothing can be created."
  }
}

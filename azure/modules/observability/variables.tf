variable "name_prefix" {
  description = "Base name produced by the naming module."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group the workspace is created in."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "retention_in_days" {
  description = <<-EOT
    Days ingested data is kept before it is dropped. Defaults to the Azure
    floor: a lab does not need history, and retention is the line on this
    resource that actually costs money.
  EOT
  type        = number
  default     = 30

  validation {
    condition     = var.retention_in_days >= 30 && var.retention_in_days <= 730
    error_message = "Azure allows 30 to 730 days."
  }
}

variable "tags" {
  description = "Tags produced by the naming module."
  type        = map(string)
}

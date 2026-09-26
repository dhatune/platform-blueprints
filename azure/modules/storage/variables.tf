variable "storage_base" {
  description = "Alphanumeric base name from the naming module."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group the account is created in."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "replication_type" {
  description = <<-EOT
    Redundancy profile. LRS costs least and keeps three synchronous copies
    within a single datacenter -- it survives a disk failure, not the loss of
    the datacenter itself. GZRS survives the loss of a zone and, with its
    asynchronous copy in a second region, the loss of the region too. The
    archive tier is unavailable on ZRS, GZRS and RA-GZRS; this module's
    lifecycle rule accounts for that (see main.tf).
  EOT
  type        = string

  validation {
    condition     = contains(["LRS", "ZRS", "GRS", "GZRS", "RAGRS", "RAGZRS"], var.replication_type)
    error_message = "replication_type must be one of LRS, ZRS, GRS, GZRS, RAGRS or RAGZRS."
  }
}

variable "soft_delete_days" {
  description = "Days a deleted or overwritten blob version remains recoverable."
  type        = number
  default     = 14

  validation {
    condition     = var.soft_delete_days >= 1 && var.soft_delete_days <= 365
    error_message = "Azure allows 1 to 365 days."
  }
}

variable "container_name" {
  description = "Container holding the object repository."
  type        = string
  default     = "objects"
}

variable "cool_after_days" {
  description = "Days after which an unmodified blob moves to the cool tier."
  type        = number
  default     = 90
}

variable "archive_after_days" {
  description = "Days after which an unmodified blob moves to the archive tier."
  type        = number
  default     = 365
}

variable "tags" {
  description = "Tags produced by the naming module."
  type        = map(string)
}

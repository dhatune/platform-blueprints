variable "name_prefix" {
  description = "Base name produced by the naming module. Used only for link names."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group the zones are created in. Private DNS zones are global; the group only holds them."
  type        = string
}

variable "zone_names" {
  description = <<-EOT
    Fully qualified private DNS zone names. These are dictated by Azure, one per
    service, and cannot be chosen freely: a private endpoint only resolves if the
    zone carries the exact name the service expects.
  EOT
  type        = list(string)
}

variable "vnet_ids" {
  description = "Virtual networks that must resolve these zones, keyed by a logical name such as hub or spoke."
  type        = map(string)
}

variable "tags" {
  description = "Tags produced by the naming module."
  type        = map(string)
}

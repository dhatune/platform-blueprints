variable "name_prefix" {
  description = "Base name produced by the naming module."
  type        = string
}

variable "service_key" {
  description = "Short logical name of the service this endpoint fronts, used in the resource name."
  type        = string
}

variable "location" {
  description = "Azure region. No default on purpose."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group the endpoint is created in."
  type        = string
}

variable "subnet_id" {
  description = <<-EOT
    Subnet holding the endpoint. It should have private_endpoint_network_policies
    set to Enabled, so the subnet's network security group and any application
    security group the endpoint joins are actually evaluated against traffic to
    and from it, rather than bypassed.
  EOT
  type        = string
}

variable "target_resource_id" {
  description = "Identifier of the service being fronted."
  type        = string
}

variable "subresource_name" {
  description = <<-EOT
    Which sub-resource of the target to connect to. Azure dictates the value per
    service -- blob, vault, registry -- and rejects anything else.
  EOT
  type        = string
}

variable "private_dns_zone_id" {
  description = <<-EOT
    Zone the endpoint registers its A record in. Without it the endpoint is
    created, the name still resolves publicly, and nothing reports an error.
  EOT
  type        = string
}

variable "tags" {
  description = "Tags produced by the naming module."
  type        = map(string)
}

variable "application_security_group_ids" {
  description = <<-EOT
    Application security groups this endpoint joins, so a network security
    rule elsewhere can target the group as a destination instead of the whole
    subnet -- letting one rule reach this endpoint without also reaching every
    other endpoint the same subnet happens to hold. Empty by default: joining
    a group is a deliberate choice per endpoint, not a blanket default every
    endpoint should carry.
  EOT
  type        = list(string)
  default     = []
}

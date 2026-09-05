variable "organization_id" {
  description = "Numeric organization ID."
  type        = string
}

variable "billing_account" {
  description = "Billing account ID."
  type        = string
  sensitive   = true
}

variable "dns_project" {
  description = <<-EOT
    Project holding the public DNS zone. Deliberately not this stack's: the
    zone outlives every lab, and ADR 26 is about what a controller may do to a
    zone it does not own.
  EOT
  type        = string
}

variable "dns_domain" {
  description = "Subtree of the zone this lab may publish into."
  type        = string
}

variable "region" {
  description = "Primary region."
  type        = string
  default     = "us-east1"
}

variable "zone" {
  description = "Zone for the cluster's single control plane."
  type        = string
  default     = "us-east1-b"
}

variable "suffix" {
  description = <<-EOT
    Short unique string appended to every generated project ID.

    A destroyed project's identifier is held for thirty days, so a rerun inside
    that window needs a value that has not been used before.
  EOT
  type        = string
}

variable "machine_type" {
  description = "Node machine type, the same in both environments."
  type        = string
  default     = "e2-standard-4"
}

variable "node_count" {
  description = "Nodes per cluster."
  type        = number
  default     = 2
}

variable "enabled_environments" {
  description = <<-EOT
    Environments this apply builds.

    Development is built and verified alone first, then production is added.
    Narrowing this list after both exist will destroy the one removed.
  EOT
  type        = list(string)
  default     = ["dev", "prod"]
}

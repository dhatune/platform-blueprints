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

variable "acme_email" {
  description = <<-EOT
    Address the certificate authority writes to before a certificate expires.

    It is here rather than in the manifests so that every value an environment
    needs comes from one file, and the manifests are generated from the stack
    rather than filled in by hand.
  EOT
  type        = string
}

variable "dns_parent_zone" {
  description = <<-EOT
    Name of the managed zone that owns the domain, in dns_project. The
    per-environment zones are delegated from it.
  EOT
  type        = string
}

variable "production_deletion_policy" {
  description = <<-EOT
    Whether production refuses to be destroyed. ADR 28.

    PREVENT is the answer for anything holding something that cannot be rebuilt
    from this repository. Changing it to DELETE is how a teardown is allowed,
    and it is a commit rather than a prompt so that the decision has an author
    and a date.

    It also governs the shared project and the folders, because an environment
    that cannot be removed leaves them behind with nothing in them.
  EOT
  type        = string
  default     = "PREVENT"

  validation {
    condition     = contains(["PREVENT", "DELETE"], var.production_deletion_policy)
    error_message = "Must be PREVENT or DELETE."
  }
}

variable "project_id" {
  description = "Project that will hold the service, its database and its bucket."
  type        = string
}

variable "region" {
  description = "Region for the service and the database. Keep them in the same one."
  type        = string
  default     = "us-east1"
}

variable "name" {
  description = "Base name for the service and every resource derived from it."
  type        = string
  default     = "vaultwarden"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,28}[a-z0-9]$", var.name))
    error_message = "Must be lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "image" {
  description = <<-EOT
    Container image, pinned by digest. Resolve the digest for the tag you have
    actually reviewed rather than copying one from a document:
      crane digest vaultwarden/server:<tag>
  EOT
  type        = string

  validation {
    # The image is refused unless it carries a digest. A tag can be moved to
    # point at a different image after review; a digest cannot.
    condition     = can(regex("@sha256:[0-9a-f]{64}$", var.image))
    error_message = "Image must be pinned by digest, not by tag alone."
  }
}

variable "domain" {
  description = "Public domain the service is served on, used to build links in email."
  type        = string
}

variable "network_id" {
  description = "VPC the service reaches the database through."
  type        = string
}

variable "subnetwork_id" {
  description = "Subnetwork used for direct VPC egress."
  type        = string
}

variable "db_tier" {
  description = "Cloud SQL machine type. The workload is small; the floor is availability, not throughput."
  type        = string
  default     = "db-g1-small"
}

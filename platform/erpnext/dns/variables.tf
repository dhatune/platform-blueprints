variable "project_id" {
  description = "Project holding the zone. Should outlive any cluster."
  type        = string
}

variable "zone_name" {
  description = "Resource name of the managed zone."
  type        = string
}

variable "domain" {
  description = "Subdomain this zone is authoritative for, without a trailing dot."
  type        = string

  validation {
    condition     = !endswith(var.domain, ".")
    error_message = "Write it without the trailing dot; it is added where it is needed."
  }
}

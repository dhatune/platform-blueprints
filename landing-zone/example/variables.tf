variable "organization_id" {
  description = "Numeric organisation ID."
  type        = string
}

variable "billing_account" {
  description = "Billing account ID."
  type        = string
  sensitive   = true
}

variable "quota_project" {
  description = "Project that API quota and billing are attributed to."
  type        = string
}

variable "region" {
  description = "Primary region."
  type        = string
  default     = "us-east1"
}

variable "project_prefix" {
  description = "Prefix for generated project IDs, to keep them unique and recognisable."
  type        = string
}

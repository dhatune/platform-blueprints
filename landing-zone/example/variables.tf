variable "organization_id" {
  description = "Numeric organization ID."
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

variable "allowed_customer_ids" {
  description = <<-EOT
    Cloud Identity customer IDs allowed to appear in IAM policies. These look
    like C0xxxxxxx and are not domain names.
  EOT
  type        = list(string)
}

variable "applier_service_account" {
  description = "Email of the service account that applies infrastructure changes."
  type        = string
}
